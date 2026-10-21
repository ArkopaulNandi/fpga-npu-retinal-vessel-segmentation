# Memory Architecture — Buffers, CNM BRAM Banks, and Partial Sums

**Status:** Design description based on the project architecture notes and available memory RTL excerpts. Verify every detail against the current source before treating it as a final interface contract.

## 1. Purpose

The memory subsystem is intended to keep the compute array supplied with activations and weights while retaining intermediate partial sums on chip. Its central goal is to reduce repeated external-memory transfers and localize data movement near the 4×4 PE array.

The proposed path is:

```text
External Memory
      |
     DMA
      |
  +---+------------------+
  |                      |
Activation Buffer     Weight Buffer
  |                      |
Activation Ping-Pong  Weight Ping-Pong
  |                      |
Activation CNM Banks  Weight CNM Banks
  |                      |
  +------> 4x4 PE Array <+
                 |
          Partial-Sum BRAMs
                 |
          Final accumulated data
```

This is the intended organization. It does not by itself prove that DMA, external memory, all buffers, and the compute array are fully integrated in the current RTL.

## 2. Memory hierarchy and responsibilities

| Level | Intended contents | Main purpose | Main risk |
|---|---|---|---|
| External memory / host source | Image tensors, model weights, large intermediate tensors if used | Capacity beyond FPGA on-chip storage | Transfer latency and bandwidth |
| DMA / staging path | Transfer bursts or staged data | Decouple source transactions from compute schedule | Backpressure, burst completion, address/control errors |
| Activation buffer | Input/feature-map values | Stage activations before compute | Insufficient bandwidth or capacity |
| Weight buffer | Kernel/model weights | Stage weights before compute | Refill latency and precision packing errors |
| Ping-pong buffers | Current and next activation/weight tile | Overlap loading with consumption | Ownership races and premature swaps |
| CNM activation banks | Values supplied to PE rows | Local parallel activation access | Bank conflicts or address misalignment |
| CNM weight banks | Values supplied to PE columns | Local parallel weight access | Incorrect lane mapping or precision decode |
| Partial-sum BRAM banks | Running sums across reduction/K tiles | Preserve intermediate sums without off-chip round trips | Read-modify-write latency and accumulator overflow |
| Output buffer | Final/intermediate output values | Decouple compute completion from output consumer | Output backpressure or overwrite |

Capacity, port count, data width, depth, and exact mapping are parameters of the implementation and should be recorded from the RTL rather than assumed globally.

## 3. CNM BRAM bank organization

The memory design notes describe a parameterized CNM bank module with parameters similar to:
- `NUM_BANKS` (default shown in the design notes as 4)
- `DATA_WIDTH` (default shown as 8 bits)
- `DEPTH` (default shown as 1024)
- `ADDR_WIDTH`, typically derived from `$clog2(DEPTH)`

The module has separate activation and weight storage. The described organization maps each activation bank to a PE-array row and each weight bank to a PE-array column. For a four-row/four-column array, four activation lanes and four weight lanes can be presented in parallel.

Conceptually:

```text
Activation bank 0 ---> PE row 0
Activation bank 1 ---> PE row 1
Activation bank 2 ---> PE row 2
Activation bank 3 ---> PE row 3

Weight bank 0 -------> PE column 0
Weight bank 1 -------> PE column 1
Weight bank 2 -------> PE column 2
Weight bank 3 -------> PE column 3
```

The actual meaning of each lane depends on the array's operand-routing convention. Confirm lane order, row/column direction, and whether one address is shared across banks from the RTL and a directed test.

The available excerpt uses registered read-data arrays and produces read-valid signals from the read-enable signals. That implies a synchronous-read contract: the consumer must use the data with the matching delayed control/valid signal. Verify the exact edge and latency in simulation, because a valid pulse that is one cycle misaligned can silently pair the wrong activation or weight with a PE operation.

## 4. Addressing and banking

For a memory with depth `DEPTH`, the minimum address width is:

\[
ADDR\_WIDTH=\max(1,\lceil\log_2(DEPTH)\rceil)
\]

`$clog2(DEPTH)` is the SystemVerilog ceiling-log function. The minimum-one-bit guard avoids a zero-width vector when depth is one. This width calculation does not validate the address: if `DEPTH` is not a power of two, some binary address values may exceed the legal range and must be rejected or prevented by control logic.

Document the following for each memory:
- Address unit: element index, byte address, or tile index.
- Address stride between rows, columns, channels, and tiles.
- Legal address range.
- Whether banks share one address or use independent addresses.
- Read latency and whether read data holds when read enable is low.
- Read-during-write behavior for same-address collisions.
- Reset behavior of output registers versus memory contents.
- Whether the RTL reliably infers the intended BRAM primitive.

Do not reset every BRAM location unless there is a deliberate reason; resetting a large inferred array can prevent efficient BRAM inference. Reset control/status and output registers where required, and initialize memory contents through a supported initialization or testbench mechanism.

## 5. Ping-pong buffer protocol

The memory notes describe independent active-bank selection and ready flags for activation and weight tiles. The intended protocol is:

1. Compute consumes the active bank only when its `*_tile_ready` status is asserted.
2. The loader writes the inactive bank only when its `*_load_enable` permits it.
3. When a tile is completely loaded, the corresponding inactive-bank ready flag is asserted.
4. A swap request changes which bank is active, but only when the new bank is ready and the old tile is safe to release.
5. Once computation has consumed the active tile, its ready flag is cleared so it can be refilled.

Illustrative ownership states:

```text
Bank A: ACTIVE / COMPUTE ---- tile consumed ----> FREE / LOAD
Bank B: FREE / LOAD --------- tile loaded -------> READY / WAIT
                                      swap
Bank A: FREE / LOAD <----------------------------- Bank B: ACTIVE / COMPUTE
```

Activation and weight ping-pong ownership may be independent in the described design. This is useful if activations and weights have different refill times, but it also means their active tile indices can become inconsistent unless the scheduler associates the correct activation tile and weight tile with the same compute command.

### Required safety properties

- Never write a bank while the compute engine is reading it.
- Never swap to a bank that is not fully loaded.
- Do not clear a ready flag before the consumer has finished.
- A swap request should have an unambiguous acceptance event; do not repeatedly toggle the bank on a held-high request.
- Define what happens if load-complete and swap occur in the same cycle.
- Define whether reset cancels an in-progress load/compute operation.
- Keep activation and weight tile IDs or sequence numbers aligned when a computation requires a matched pair.

A testbench should randomize load completion, compute completion, and swap requests while checking these invariants.

## 6. Partial-sum BRAM organization

The design notes describe one partial-sum memory bank per PE-array output column. With four columns, the intended organization has four running-sum banks, each with a parameterized data width and depth. The excerpt shows registered inputs/address/control and a sequence resembling read partial sum, add incoming column value, and write the updated value.

For each output position, convolution/GEMM-style reduction may be split across K/reduction tiles. If tile \(k\) produces partial sum \(P_k\), then:

\[
S_0=0,\qquad S_{k+1}=S_k+P_k
\]

where:
- \(P_k\) is the contribution from the current reduction tile.
- \(S_k\) is the accumulated result before the tile.
- \(S_{k+1}\) is the accumulated result after the tile.

The control contract must clearly distinguish:
- **First reduction tile:** initialize or replace the previous sum with the new contribution.
- **Middle reduction tile:** add the new contribution to the stored sum.
- **Last reduction tile:** produce the completed output after the correct update.
- **Single-tile reduction:** both initialize and finalize in the same logical operation.

The available excerpt's names (`acc_clr`, `acc_en`, `last_k_tile`, `psum_valid`) suggest these roles, but the exact behavior must be checked against the current RTL. In particular, verify whether the first tile stores the incoming `psum_in` or a prior `psum_sum` register; test this explicitly because an incorrect initialization path can drop the first tile's contribution.

### Width and overflow

If signed operands have widths \(W_a\) and \(W_w\), the full signed product generally requires up to \(W_a+W_w\) bits. Summing \(N\) worst-case products requires additional guard bits; a common conservative bound is:

\[
W_{acc}\approx W_a+W_w+\lceil\log_2(N)\rceil
\]

This is a sizing estimate, not a substitute for deriving bounds from the actual quantization ranges and number of summed terms. Document whether accumulation uses truncation, wraparound, saturation, or explicit scaling.

## 7. Dataflow and reuse

The project targets a weight-stationary PE dataflow: weights are loaded to local PE registers and reused while activations move through the array. Local storage is useful only when the schedule actually reuses each fetched value. Measure:
- External bytes read per output tile.
- Activation and weight bank reads per compute cycle.
- Number of MACs per activation/weight fetch.
- Partial-sum read/write transactions per output.
- PE stall cycles caused by data-not-ready conditions.
- Whether the active buffer is refilled concurrently with compute.

A buffer can consume BRAM but provide little benefit if each tile is used only once or if the controller cannot overlap load and compute.

## 8. Bandwidth and throughput analysis

If the array ideally consumes four activation values and four weight values each cycle, the raw operand demand at data width \(W\) is approximately:

\[
B_{operand}=8W \text{ bits/cycle}
\]

This is only an illustrative interface-level estimate; the actual demand depends on the routing schedule, precision packing, and whether operands are broadcast/reused. At clock frequency \(f\), multiply the per-cycle bit demand by \(f\) to estimate required internal bandwidth.

The memory system must meet the compute schedule's demand, not merely have sufficient total capacity. Four banks with a shared address can provide parallel lanes only if the access pattern maps conflict-free to those banks.

## 9. Verification plan

### Unit tests
- Read/write each bank independently.
- Read all banks at the same address and verify lane ordering.
- Check synchronous read latency and valid alignment.
- Exercise minimum/maximum addresses and invalid addresses.
- Check clock-enable pauses do not advance memory controls unexpectedly.
- Verify reset behavior of valid outputs and registered data.
- Check same-address read/write behavior if it is architecturally relevant.
- Test precision unpacking and sign extension in the upstream weight path.

### Ping-pong tests
- Load bank 0 while bank 1 is active, then swap.
- Attempt swap before load completion.
- Hold swap request high for multiple cycles.
- Complete loading and consuming in the same cycle.
- Independently delay activation and weight refill.
- Apply reset mid-transaction.
- Check that no active bank is overwritten.

### Partial-sum tests
- One reduction tile.
- Multiple reduction tiles.
- First/middle/last tile controls.
- Negative and maximum-magnitude values.
- Overflow boundary cases.
- Back-to-back addresses and valid pulses.
- Result-valid timing and final-result alignment.

## 10. FPGA implementation notes

- Confirm the target FPGA part and Vivado version before recording BRAM capacity or timing.
- Inspect synthesis reports to ensure arrays infer BRAM rather than LUT RAM or flip-flops.
- Inspect read/write port inference and any memory inference warnings.
- Review fanout of bank enables, shared addresses, and reset/clock-enable signals.
- Consider local placement of BRAM banks near the PE array, but validate with placement/routing reports rather than relying on logical hierarchy alone.
- Record BRAM count, LUT/FF use, DSP use, achieved clock, worst slack, and the critical path.
- If a synchronous BRAM read adds a cycle, pipeline the matching address/control/valid metadata rather than trying to remove the memory latency through combinational logic.

## 11. Open issues to close before publication

1. Publish a precise memory map with depth, width, ports, and address units for every buffer.
2. Specify the external-memory/DMA interface and burst behavior.
3. Prove ping-pong ownership correctness with assertions or randomized tests.
4. Validate the partial-sum first-tile initialization and final-tile result timing.
5. Quantify traffic reduction relative to a clearly defined baseline.
6. Show that ping-pong loading overlaps compute in cycle traces or counters.
7. Report actual BRAM inference and timing results from the selected FPGA.
