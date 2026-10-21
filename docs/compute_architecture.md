# Compute Architecture — MAC Units, 4×4 Systolic Array, and Accumulation

**Status:** Architectural description for the intended compute subsystem. Confirm exact datapaths, parameters, pipeline stages, and control behavior from the current RTL and passing tests.

## 1. Purpose

The compute core is intended to execute the multiply-accumulate-heavy portion of CNN layers. The initial structure is a 4×4 systolic processing-element array containing 16 PEs, with local operand registers, MAC datapaths, partial-sum state, and routing/control logic. A reduction/accumulation subsystem combines results across output columns and across reduction tiles.

The core should be treated as a configurable arithmetic engine. Retinal-vessel-specific behavior belongs in the model, frontend, layer configuration, and final segmentation path—not hard-coded into the MAC datapath.

## 2. Compute hierarchy

```text
Compute Core
 ├── Activation/Weight Input Routing
 ├── 4 x 4 PE Array
 │    ├── PE[0][0] ... PE[0][3]
 │    ├── PE[1][0] ... PE[1][3]
 │    ├── PE[2][0] ... PE[2][3]
 │    └── PE[3][0] ... PE[3][3]
 │
 │    Each PE is intended to contain:
 │      - activation/input register
 │      - weight register
 │      - multiplier + accumulator (MAC)
 │      - partial-sum register
 │      - routing/control logic
 │
 ├── PE Interconnect / Systolic Routing
 └── Reduction and Accumulation
```

The system hierarchy also names CNN operators such as bias, reconfigurable activation, pooling, scaling, and quantization. These operators may be separate modules or later integration stages; their presence in the hierarchy is not proof of implementation.

## 3. Processing element (PE)

A PE performs the core arithmetic operation:

\[
p_{next}=p_{current}+a\times w
\]

where:
- \(a\) is the signed or unsigned activation operand, as defined by the RTL.
- \(w\) is the weight operand.
- \(p_{current}\) is the current partial sum.
- \(p_{next}\) is the updated partial sum.

The equation is conceptual. Exact operand signedness, product width, accumulator width, enable behavior, reset semantics, and overflow policy must match the RTL contract.

### Intended internal blocks

| Block | Purpose | Design questions |
|---|---|---|
| Input/activation register | Holds activation data aligned to the compute cycle | Does it capture every enabled cycle or only on a valid/enable handshake? |
| Weight register | Holds weight for local reuse | When is it loaded, and how long is it stationary? |
| Multiplier | Computes activation × weight | Inferred DSP or LUT implementation? Supported precision modes? |
| Accumulator / PSUM register | Retains running sum | Clear/load/accumulate priority and overflow behavior? |
| Routing logic | Passes or selects operands/partial sums | Neighbor direction, bypass path, boundary behavior? |
| Control logic | Enables loading, MAC execution, clearing, and draining | Are control signals pipelined with operands? |

Do not assume a PE maps to one DSP slice. DSP mapping depends on operand widths, coding style, synthesis settings, and target device. Low-precision packing may use DSPs, LUTs, or multiple logical operations per physical DSP, but this must be demonstrated in synthesis reports.

## 4. 4×4 array and nominal peak

A 4×4 array contains 16 PEs. If every PE completes one MAC every clock cycle, the nominal peak is:

\[
16\ \text{MAC/cycle}
\]

At an achieved clock frequency \(f\), the theoretical ceiling is:

\[
T_{peak}=16f\ \text{MAC/s}
\]

For example, this formula is intended to be populated with the *measured achieved clock*, not an assumed target frequency. It is not equivalent to 16 multiply-accumulate operations of arbitrary precision per cycle if precision modes alter the number of physical arithmetic operations.

Actual throughput is lower when:
- The array is filling or draining.
- Activations or weights are unavailable.
- A tile is smaller than the array.
- The scheduler inserts bubbles.
- Partial-sum memory or post-processing becomes the bottleneck.
- The chosen precision mode changes the effective arithmetic packing.
- The result consumer applies backpressure.

Report useful MACs divided by measured elapsed time, and report PE utilization separately.

## 5. Weight-stationary dataflow

The project describes a weight-stationary systolic organization. In this strategy, weights are loaded into PE-local registers and reused across multiple activation cycles. Activations move through the array according to the systolic schedule, while partial sums are retained or propagated according to the implemented routing.

```text
Weight load phase:
  weight tile --> PE-local weight registers

Compute phase:
  activation stream --> PE array
  each PE computes activation * retained weight
  partial sums update/propagate
  completed tile results drain to reduction/accumulation
```

### Why choose weight-stationary?

- Reusing weights locally can reduce repeated weight reads.
- PE-local registers can reduce repeated global distribution of the same weight.
- Regular neighbor-to-neighbor data movement can be easier to pipeline than a fully connected crossbar.
- The design is compatible with a tiled CNN/GEMM implementation.

### Trade-offs

- Loading a new weight tile has overhead.
- PE-local weight storage and routing add registers/control.
- A weight-stationary schedule may not be optimal for every layer shape.
- Partial-sum movement and activation delivery can become the bottleneck instead.
- A 4×4 array has limited spatial parallelism; large layers require repeated tiles.

The term “weight-stationary” should be supported by an RTL-level schedule or waveform showing weight registers held stable while multiple activation operands are processed. A design label alone is not verification.

## 6. Systolic timing intuition

A systolic array uses regular, clocked movement of data between neighboring processing elements. The exact latency depends on whether activation and partial-sum values move horizontally, vertically, or through a separate routing network. The current design notes identify activation, weight, and partial-sum routing modules; the exact direction and cycle schedule must be documented from those RTL modules.

For a generic operation:
1. Load the weight tile and wait for load completion.
2. Start the activation stream.
3. Each valid compute cycle updates the relevant PE MAC state.
4. Track valid/control metadata through any pipeline stages.
5. Stop issuing new inputs after the tile's final activation.
6. Drain in-flight values and partial sums.
7. Accumulate outputs and mark the tile complete.

This sequence is conceptual and should be reconciled with the implemented controller FSMs.

### Cycle-by-cycle worksheet

Use a waveform or table in the repository to document:
- Cycle number.
- `compute_start`/PE enable.
- Activation and weight values at each array boundary.
- PE-local weight-register loads.
- MAC valid/enable.
- Partial-sum values.
- Array drain state.
- Result-valid and tile-done.

Avoid publishing a single “cycles per tile” figure until start/end events are defined and the fill/drain protocol is tested.

## 7. MAC arithmetic contract

For a signed \(W_a\)-bit activation and signed \(W_w\)-bit weight, a full-precision signed product generally needs \(W_a+W_w\) bits. Summing many products needs extra headroom. A conservative estimate for \(N\) terms is:

\[
W_{acc}\approx W_a+W_w+\lceil\log_2(N)\rceil
\]

where \(N\) is the maximum number of products accumulated before the accumulator is rescaled or cleared. This estimate assumes a worst-case growth bound; derive the final width from the actual value ranges and quantization scheme.

The design must specify:
- Signed versus unsigned interpretation.
- Width of multiplier output.
- Width of accumulator and intermediate expression.
- Whether SystemVerilog expression sizing/sign extension is explicit.
- Overflow behavior: wrap, saturate, or wider result.
- Accumulator clear/load/accumulate priority.
- Clock-enable behavior.
- Reset polarity and reset value.
- Valid/ready protocol and output latency.

For quantized inference, a later scaling/rounding/saturation step may be required to return the accumulator to the activation/feature-map width. Do not silently truncate the accumulator without documenting the numerical effect.

## 8. Precision modes and packed weights

The weight-routing design notes describe selectable INT8/INT4/INT2 unpacking with sign extension. This should be considered an intended feature until verified in the current RTL and tests.

For every precision mode, document:
- Number of logical weights packed into each stored word.
- Bit ordering and lane ordering.
- Signed encoding.
- Sign-extension rule.
- How a logical weight index maps to a memory address and bit slice.
- Whether activation precision changes too.
- Whether the same PE datapath is reused or arithmetic is spatially packed.
- Numerical equivalence and resource impact.

A precision selector that only changes unpacking does not automatically increase MAC throughput. Higher throughput requires the datapath and schedule to exploit multiple narrow operations per cycle, if that is the design goal.

## 9. Reduction and accumulation

The project architecture includes parallel reduction/accumulation and partial-sum BRAM storage. The compute array's result interface must specify whether it produces:
- One result per PE,
- One partial sum per column,
- A reduced vector,
- Or another arrangement.

The available memory notes describe one partial-sum memory per array column. If four column results are emitted per accumulation step, the accumulator must associate each value with the correct output address and reduction-tile sequence.

Important correctness conditions:
- First K/reduction tile initializes the sum.
- Intermediate tiles add to the stored sum.
- Final tile emits the fully accumulated result.
- Result-valid aligns with the data and output address.
- Consecutive output addresses cannot overwrite one another.
- Reset/abort cannot leave stale partial sums to contaminate the next operation.

The implementation should be tested against a software reference using small matrices where every expected output can be calculated independently.

## 10. Control and routing interfaces

The architecture notes identify routing/control components for activations, weights, partial sums, and tile management. The intended responsibilities are:
- **Activation routing:** derive input/window coordinates, handle padding, generate BRAM addresses, and align activation data/validity.
- **Weight routing:** request packed weight words, unpack the selected precision, sign-extend as required, and align data with the compute schedule.
- **Partial-sum routing:** delay addresses/control as needed and deskew column results so each sum corresponds to the correct output position.
- **Tile management:** sequence weight load, stream/compute, drain, tile completion, and buffer swap events.

These are design-note responsibilities. Verify exact module ports and state transitions from the source. In particular, ensure that synchronous BRAM latency is reflected in all corresponding address, valid, padding, and tile metadata pipelines.

## 11. Verification plan

### MAC unit
- Positive × positive, positive × negative, negative × negative.
- Zero operands and maximum/minimum representable values.
- Accumulate multiple products.
- Clear and accumulate asserted in combinations defined by the contract.
- Clock-enable pauses.
- Reset during idle and during active operation.
- Overflow/truncation/saturation boundary cases.
- Randomized operands compared against a width-accurate reference model.

### PE
- Weight load and hold behavior.
- MAC enabled and disabled cycles.
- Partial-sum clear and reload.
- Control/valid alignment.
- Boundary routing and bypass behavior.
- Consecutive tiles with different weights.
- No stale state leakage between tiles.

### Array
- Directed small matrix multiply with a software reference.
- Fill, steady-state, and drain.
- All PEs active and partial-array utilization cases.
- Back-to-back tiles and buffer swaps.
- Random stalls in operand supply.
- Comparison of every output and cycle count.

### Accumulation
- Single and multiple reduction tiles.
- Correct first/middle/last tile semantics.
- Repeated output addresses and consecutive outputs.
- Negative partial sums and overflow boundaries.
- Output-valid pulse and final result alignment.

Tests should be self-checking and should return a non-zero simulator failure status on mismatch.

## 12. FPGA implementation considerations

- **DSP usage:** depends on multiplier width, number of simultaneous MACs, precision mode, and synthesis inference.
- **LUT/FF usage:** PE control, routing, pipeline metadata, counters, and arithmetic not mapped to DSPs.
- **BRAM usage:** activation/weight storage and partial sums; confirm inference in reports.
- **Critical path candidates:** multiplier-to-accumulator path, reduction tree, high-fanout enables, address-generation arithmetic, and routing muxes.
- **Timing closure:** pipeline long arithmetic or wide reduction paths; preserve alignment of data and control when adding stages.
- **Placement/routing:** local PE neighbor connections are usually easier to route than global all-to-all paths, but fanout and bank placement still need report-based review.
- **Clock enable:** use a consistent enable contract; verify that every pipeline stage either advances together or has valid/ready buffering to tolerate independent stalls.

Do not report DSP counts, maximum frequency, or power until they are measured for a specific device and implementation run.

## 13. Research opportunities

| Opportunity | Problem | Proposed investigation | Main challenge |
|---|---|---|---|
| Precision-aware MAC | Low precision may save storage but not necessarily improve compute throughput | Compare INT8/INT4/INT2 arithmetic mapping and numerical accuracy | Correct packed arithmetic and fair accuracy comparison |
| Shape-aware tiling | Small or irregular layers may underutilize a 4×4 array | Tune tile shapes and measure useful PE-cycles | Scheduler complexity and extra control |
| Overlapped load/compute | Buffer refill may stall the array | Measure ping-pong overlap and quantify hidden transfer cycles | Correct bank ownership and independent completion timing |
| Partial-sum optimization | BRAM read-modify-write can limit accumulation rate | Explore local accumulator registers, banking, or pipelined accumulation | Area growth and hazard handling |
| Dataflow comparison | Weight-stationary may not be optimal for all layers | Compare against output-stationary or alternative schedules | More control modes and apples-to-apples measurement |
| Performance counters | Bottlenecks may be invisible from total latency alone | Add counters for PE active cycles, memory waits, and drain cycles | Correct event definitions and low-overhead instrumentation |

## 14. Required evidence before claiming results

For each reported result, retain:
- RTL commit/hash and testbench version.
- Operand dimensions and precision.
- Reference model and test vectors.
- Simulator and command used.
- Synthesis/implementation tool version and exact FPGA part.
- LUT, FF, DSP, BRAM/URAM usage.
- Clock constraint, achieved clock, and timing slack.
- Cycle count definitions and measured output throughput.
- Any application-level metric and the exact dataset/split/preprocessing used.

No synthesis, timing, power, or segmentation-accuracy result is claimed by this document.
