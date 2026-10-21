# Verification Plan — FPGA-Based NPU for Retinal Vessel Segmentation

**Document status:** Initial verification plan  
**Design under test (DUT):** SystemVerilog-based NPU architecture with a 4×4 systolic PE array, parameterized MAC units, BRAM-based activation/weight/partial-sum storage, ping-pong buffering, and controller/routing logic.  
**Application target:** CNN-based retinal vessel segmentation.  
**Important scope note:** This plan defines the verification work to perform. It does not claim that tests have already passed or that all listed subsystems are integrated.

---

## 1. Objectives

The verification process must establish, with repeatable evidence, that:

1. Individual RTL modules implement their documented functional contracts.
2. Synchronous reset, clock-enable, valid/ready, and stall behavior are correct.
3. Arithmetic results match an independent reference model for the supported precision and overflow rules.
4. Activation, weight, and partial-sum data remain aligned with their addresses and control signals through memory latency and routing pipelines.
5. Ping-pong buffers do not permit simultaneous producer/consumer ownership of the same bank.
6. Controllers complete valid operations, handle waits, and do not deadlock under legal timing variations.
7. The PE array computes the intended tiled operation and handles fill, steady-state, drain, and tile boundaries correctly.
8. The integrated RTL agrees with a software reference on representative matrix/convolution workloads.
9. Synthesis and FPGA implementation reports support claims about resource usage and timing.
10. End-to-end segmentation quality is evaluated separately from RTL arithmetic correctness.

Verification must be layered. A successful compile is not a passing functional test; a passing unit test is not proof of top-level integration; and synthesis success is not proof of hardware correctness.

## 2. Verification levels

| Level | DUT scope | Main purpose | Evidence |
|---|---|---|---|
| L0 — Static checks | Source files and module interfaces | Catch syntax, width, latch, and elaboration problems | Compiler/linter logs |
| L1 — Unit | Individual MAC, PE, routing, buffer, and controller modules | Check local behavior in isolation | Self-checking unit testbench results |
| L2 — Subsystem | PE array, CNM memory path, ping-pong + scheduler, frontend pipeline | Check timing and handshakes across connected modules | Subsystem tests and waveforms |
| L3 — Integration | NPU top-level or the largest available integrated hierarchy | Check end-to-end command/data/control behavior | Regression logs and reference comparison |
| L4 — Implementation | Synthesized and implemented FPGA design | Check resource inference and timing constraints | Vivado reports and timing analysis |
| L5 — Application | Retinal-image inference and segmentation evaluation | Check application output against reference labels/software | Dataset protocol, masks, and metrics |
| L6 — Hardware | Physical FPGA board, if available and in scope | Confirm programmed design behavior | Board setup, captured outputs, and repeatable procedure |

If the current design does not yet contain a fully connected top-level or application datapath, mark the relevant levels **not yet applicable** rather than substituting an isolated module test and calling it end-to-end verification.

## 3. Verification environment

### 3.1 RTL simulation

Use the simulator supported by the current project setup. Keep a documented command or script for each test. The testbench should:
- Generate the DUT clock and reset.
- Drive inputs on a defined clock phase to avoid races.
- Sample outputs after the relevant sequential update.
- Use assertions or explicit comparisons.
- Stop with a fatal/error status on a mismatch.
- Print the test name, parameters, random seed, and first failing transaction.
- Include a timeout to detect stuck `busy` states or missing completion pulses.
- Avoid relying only on waveform inspection or `$display` output.

### 3.2 Reference models

Use an independent reference implementation for arithmetic and application checks. A Python/NumPy reference is appropriate for matrix and convolution calculations once the numerical contract is frozen. The reference must reproduce the DUT's actual:
- Signedness and operand widths.
- Weight unpacking and sign extension.
- Accumulator width.
- Overflow, saturation, truncation, rounding, and scaling.
- Padding, stride, and tensor layout.
- Activation/pooling behavior, where implemented.

Do not make the reference model copy the same RTL algorithm line-for-line; independent calculations reduce the chance of reproducing the same bug.

### 3.3 Test categories

- **Directed tests:** known hand-computable cases.
- **Boundary tests:** minimum/maximum values, first/last addresses, reset and tile boundaries.
- **Randomized tests:** reproducible random operands and legal timing variation.
- **Stress tests:** back-to-back transactions, delayed data, stalls, and concurrent buffer activity.
- **Regression tests:** all previously passing tests run after a change.
- **Differential tests:** compare RTL results with a software reference.
- **Implementation checks:** inspect synthesis and timing reports.

### 3.4 Test naming and logs

Suggested convention:

`<level>_<subsystem>_<scenario>`

Examples:
- `L1_mac_signed_corner`
- `L1_cnm_sync_read_latency`
- `L1_pingpong_swap_before_ready`
- `L2_array_fill_drain`
- `L3_matrix_reference_random`
- `L4_bram_inference_report`

Each run should record:
- Git commit/hash or source revision.
- Simulator/tool and version.
- Test name and parameter values.
- Random seed, where applicable.
- Pass/fail result.
- Summary of transactions and mismatches.
- Log path and waveform path, if generated.

---

## 4. Reset, clock-enable, and global protocol tests

These tests apply across the design, not only to one module.

| ID | Scenario | Stimulus | Expected behavior |
|---|---|---|---|
| RST-01 | Reset at startup | Assert reset before clocked operation | State/control outputs reach documented reset values |
| RST-02 | Reset during operation | Assert reset while a transaction is active | DUT returns to a defined state; no stale completion or partial result is accepted after reset |
| CE-01 | Clock enable low | Hold `clk_enable` low for multiple cycles | State and registered data covered by the enable contract hold; no unintended transaction advances |
| CE-02 | Resume after pause | Re-enable after a pause mid-operation | Operation resumes without skipped/duplicated data |
| CTRL-01 | Single-cycle start | Pulse start for one cycle | One operation begins, assuming required preconditions are met |
| CTRL-02 | Held start | Keep start high for multiple cycles | Behavior follows the documented protocol; no accidental repeated launches |
| CTRL-03 | Completion pulse | Run one operation to completion | `done`/valid behavior has documented duration and occurs exactly as specified |
| CTRL-04 | Timeout | Withhold a required ready/valid response | DUT waits or reports a defined error; testbench timeout detects unintended deadlock |

**Important:** not every module needs to reset memory contents. The test must check the documented reset contract for control and output registers, not assume every BRAM word becomes zero.

---

## 5. MAC unit verification

### 5.1 Functional tests

| ID | Test | Stimulus | Check |
|---|---|---|---|
| MAC-01 | Zero multiplication | \(a=0\), varied \(w\) | Product contribution is zero |
| MAC-02 | Identity cases | \(a=1\), \(w=1\), and negative equivalents if signed | Exact expected product |
| MAC-03 | Sign combinations | Positive/negative operand combinations | Correct signed product |
| MAC-04 | Repeated accumulation | Apply a sequence of operand pairs | Accumulator equals reference sum |
| MAC-05 | Accumulator clear | Clear before a known sequence | Previous operation does not affect result |
| MAC-06 | Clock-enable pause | Disable between MAC operations | No update while disabled if that is the contract |
| MAC-07 | Corner values | Minimum and maximum representable operands | Correct width/sign behavior |
| MAC-08 | Overflow boundary | Force result beyond nominal accumulator range | Behavior matches documented wrap/saturate/widen policy |
| MAC-09 | Back-to-back operations | Consecutive valid operand pairs | No lost or duplicated operation |
| MAC-10 | Reset recovery | Reset during/after accumulation | State returns to specified reset behavior |

### 5.2 Required arithmetic definition

Before signing off the MAC, record:
- `ACT_WIDTH`, `WEIGHT_WIDTH`, `ACC_WIDTH`.
- Signed/unsigned interpretation.
- Product width and expression sizing.
- Clear/load/accumulate priority.
- Output-valid timing.
- Overflow policy.
- Clock-enable semantics.

If these items are unspecified, the testbench cannot define an unambiguous expected answer. Treat that as a specification issue to resolve before sign-off.

### 5.3 Reference comparison

For every test vector, calculate the expected result using explicitly sized arithmetic. For randomized tests, preserve the seed and print the first failing operands, previous accumulator, control inputs, expected result, and actual result.

---

## 6. PE verification

| ID | Scenario | Stimulus | Expected result |
|---|---|---|---|
| PE-01 | Weight load | Load a known weight | Local weight state matches the loaded value |
| PE-02 | Weight stationarity | Hold weight-load inactive while applying multiple activations | Weight remains stable while MAC operations proceed |
| PE-03 | MAC enabled | Apply valid activation/weight and enable | Partial sum updates as specified |
| PE-04 | MAC disabled | Disable compute | Partial sum and pipeline state follow the specified hold behavior |
| PE-05 | Partial-sum clear | Clear before computation | Old partial sum does not contaminate the new operation |
| PE-06 | Routing | Drive distinct values at each input lane | Values emerge on the expected output lane/direction |
| PE-07 | Pipeline alignment | Change data and valid/control patterns | Results correspond to the correct transaction |
| PE-08 | Tile transition | Finish one tile, load different weights, start next tile | No state leakage between tiles |
| PE-09 | Boundary PE | Exercise array-edge routing/bypass | Boundary behavior matches the architecture |
| PE-10 | Reset mid-operation | Reset with active partial sum | PE returns to documented state |

The PE-level scoreboard should calculate expected partial sums from the exact sequence of accepted MAC operations, not simply compare the final value without tracking dropped or duplicated transactions.

---

## 7. PE-array verification

The array is the first level where a local MAC may be correct but the overall computation can still fail due to operand skew, routing, or scheduling.

### 7.1 Directed array tests

1. **All-zero input:** all completed outputs should match the reference zero result, subject to bias/initialization configuration.
2. **Small hand-computable matrix:** choose a small matrix/tile with distinct values so row/column swaps are obvious.
3. **Identity-like weights:** useful for checking lane order and data movement.
4. **Unique lane pattern:** drive a different value per row, column, and cycle to expose skew/alignment errors.
5. **Fill phase:** verify the first valid result does not occur before the required data has traversed the array.
6. **Steady state:** verify intended PE activity and expected result cadence.
7. **Drain phase:** stop new inputs and verify all in-flight work completes exactly once.
8. **Partial utilization:** use dimensions smaller than 4×4 or a partial tile if supported.
9. **Back-to-back tiles:** change weights and input data at tile boundaries.
10. **Stall injection:** pause data supply where the interface permits it and verify no transaction is lost.

### 7.2 Array-level checks

- Compare every output against an independent matrix/convolution reference.
- Verify output order and valid timing.
- Count accepted MAC operations and ensure the count agrees with the expected workload.
- Verify no stale partial sums cross between independent jobs.
- Measure cycles using a defined start event and a defined final-result event.
- Record useful PE-cycles and available PE-cycles to calculate utilization.
- Do not infer the actual systolic latency solely from the array dimensions; derive it from the implemented register/routing schedule.

---

## 8. Activation and weight routing verification

The design notes identify activation routing for coordinate/address generation and padding alignment, and weight routing for packed-weight read/unpack/sign extension. Test these separately from the PE array first.

### 8.1 Activation routing

| ID | Scenario | Check |
|---|---|---|
| AR-01 | Interior coordinate | Correct input address and data lane |
| AR-02 | Top/left boundary | Padding policy and valid alignment |
| AR-03 | Bottom/right boundary | No out-of-range address or invalid data acceptance |
| AR-04 | Stride/window movement | Coordinates advance according to configured stride/window |
| AR-05 | Padding cycle | Padded value is correct and marked valid/invalid according to contract |
| AR-06 | Synchronous BRAM latency | Address, data, padding, and valid refer to the same logical sample |
| AR-07 | Reset/enable pause | Coordinates do not advance incorrectly during reset or disabled cycles |

The precise convolution window, stride, and padding policy must be specified by the model/configuration. Do not assume “same” padding or a particular kernel size unless it is configured in the design.

### 8.2 Weight routing

| ID | Scenario | Check |
|---|---|---|
| WR-01 | INT8 mode | Correct unpacked byte and sign interpretation |
| WR-02 | INT4 mode | Correct nibble order and sign extension |
| WR-03 | INT2 mode | Correct two-bit lane order and sign extension |
| WR-04 | Negative values | Correct sign extension for each supported mode |
| WR-05 | Address sequence | No skipped/repeated packed word |
| WR-06 | Read wait | FSM waits for the corresponding memory-valid response |
| WR-07 | Mode transition | Precision change does not reuse stale decoded weights |
| WR-08 | Tile boundary | Correct first/last weight and completion indication |

Precision modes named in the design notes should be treated as supported only after these tests pass and the RTL defines the packed format.

---

## 9. CNM BRAM and buffer verification

### 9.1 CNM BRAM bank tests

- Write unique values into each bank and address.
- Read each bank individually.
- Read all activation banks at a shared address and check lane ordering.
- Read all weight banks at a shared address and check lane ordering.
- Verify synchronous read latency and valid pulse alignment.
- Exercise first and last legal addresses.
- Test non-power-of-two depth if supported and ensure illegal addresses cannot be used silently.
- Test simultaneous reads and writes according to the defined port contract.
- Check clock-enable pauses and reset behavior of output/valid registers.
- Inspect synthesis reports to confirm intended BRAM inference.

### 9.2 Ping-pong buffer tests

| ID | Scenario | Expected behavior |
|---|---|---|
| PP-01 | Load inactive bank | Loading is allowed only for a free inactive bank |
| PP-02 | Active bank protected | Writes to the bank being consumed are prevented by the protocol |
| PP-03 | Swap after ready | Active bank changes to the fully loaded bank |
| PP-04 | Swap before ready | Swap is rejected, ignored, or deferred according to the documented contract |
| PP-05 | Held swap request | One request causes at most one swap unless the protocol explicitly says otherwise |
| PP-06 | Load and consume overlap | Independent work proceeds without ownership collision |
| PP-07 | Activation/weight refill skew | Different completion times do not pair unrelated tiles |
| PP-08 | Load complete and swap same cycle | Priority is deterministic and tested |
| PP-09 | Reset mid-transfer | Ownership flags return to a defined state |
| PP-10 | Long randomized run | No bank is simultaneously owned for incompatible read/write operations |

Assertions or scoreboard invariants should check:
- A compute-active bank is not written by the loader.
- A swap target is ready before it becomes active.
- A consumed bank becomes reusable only after consumption completes.
- Activation and weight tile identities match for each compute launch.

### 9.3 Partial-sum BRAM tests

Test:
- First reduction tile initialization.
- Middle-tile accumulation.
- Final-tile output.
- Single-tile reduction.
- Consecutive output addresses.
- Negative and maximum-magnitude partial sums.
- Overflow behavior.
- `psum_valid`, `busy`, and `result_valid` timing.
- Read-modify-write latency and any address/control pipeline.
- No contamination between independent output positions or jobs.

The first-tile case deserves special attention: it must store the current partial sum as the initial value rather than accidentally retaining a stale accumulator value.

---

## 10. Controller and scheduler verification

The project hierarchy identifies a main FSM, layer controller, tile controller, dataflow controller, memory scheduler, and PE controller. Verify each module against its own transition contract, then verify their interactions.

### 10.1 Main FSM
- Reset enters the documented idle state.
- Legal start sequence enters execution.
- Completion is reported once.
- Error/invalid configuration path is defined.
- Clock enable pauses state progression consistently.
- Reset during an active transaction cancels or resets the transaction as specified.

### 10.2 Layer controller
- Correct layer index progression.
- Configuration is stable during the layer that consumes it.
- Last-layer completion produces system completion only after required output work finishes.
- Illegal layer count/configuration is handled according to contract.

### 10.3 Tile controller / tile management
- Weight-load, stream, drain, and tile-complete sequence.
- Correct tile count and last-tile detection.
- Buffer swap occurs at a safe boundary.
- No premature transition when a memory or compute completion signal is delayed.

### 10.4 Dataflow controller
- Selected dataflow/configuration drives the expected routing mode.
- Control signals remain aligned with data.
- Unsupported modes are rejected or handled deterministically.

### 10.5 Memory scheduler
- Waits for both required activation and weight tiles.
- Issues read enables and addresses as specified.
- Waits for synchronous read-valid responses before starting compute.
- Issues a single compute-start event per scheduled tile.
- Waits for compute completion before advancing.
- Handles delayed ready/valid signals without deadlock or duplicate launches.

### 10.6 PE controller
- PE load/compute/clear/drain enables are correctly sequenced.
- No MAC update occurs when disabled if the contract requires a hold.
- Completion waits for all in-flight operations to drain.

### 10.7 Controller stress tests

Randomize legal delays for tile-ready, read-valid, compute-done, and output-ready signals. Add watchdog timeouts. For each run, verify:
- Every accepted command eventually completes or produces a defined error.
- No command completes twice.
- No compute launch occurs without required data.
- Tile indices and bank ownership remain consistent.
- Reset/clock-enable behavior does not leave the FSM in an unrecoverable state.

---

## 11. System interface and frontend verification

Only run these tests if the corresponding interfaces/modules exist in the current integrated design.

### 11.1 Register bank and AXI4-Lite
- Read/write every documented address.
- Check byte strobes/write masks.
- Verify read/write responses and valid/ready backpressure.
- Check simultaneous read and write behavior where supported.
- Verify reset values and reserved-address behavior.
- Verify configuration fields drive the intended internal signals.
- Verify status, performance counters, and interrupt behavior if implemented.

Do not claim AXI protocol compliance based solely on signal names. Use protocol assertions or a suitable AXI verification component when available.

### 11.2 AXI4-Stream input/output
- Valid held while ready is low.
- Ready toggling and backpressure.
- First/last beat and packet/frame boundaries if supported.
- No dropped or duplicated beats.
- Correct data ordering.
- Reset during a stream.
- Output stalls do not corrupt data or prematurely signal completion.

### 11.3 Image frontend
- Frame dimensions and coordinate boundaries.
- Grayscale/format conversion against a software reference, if implemented.
- Normalization rounding/saturation.
- ROI boundary behavior.
- Optional filter bypass and enabled behavior.
- Tensor layout/channel order.
- Window generation, stride, and padding.
- Backpressure and valid alignment.

For each stage, test small synthetic images with known values before using full retinal images.

---

## 12. CNN operator and output verification

Run tests for each operator only if it exists in RTL.

| Operator | Tests |
|---|---|
| Bias addition | Zero bias, positive/negative bias, width and overflow boundaries |
| Activation | Values below/at/above the activation boundary; negative inputs; exact rounding |
| Pooling | Small known windows, boundary windows, tie cases, stride behavior |
| Scaling/quantization | Scale, rounding, clipping, saturation, and negative values |
| Segmentation score/formatter | Pixel ordering, output dimensions, score width and format |
| Threshold | Values below, equal to, and above the configured threshold; verify the specified comparison (`<`, `<=`, `>`, or `>=`) |
| Vessel mask | Exact binary output encoding and pixel count |
| Output buffer | Sequential addresses, overflow/full behavior, backpressure |

A threshold stage can be correct while the neural-network prediction is poor. Verify operator arithmetic separately from model quality.

---

## 13. Software-reference and application tests

### 13.1 Matrix/convolution reference

Start with tiny deterministic cases:
- A single MAC.
- A small dot product.
- A small matrix multiplication.
- A small convolution with a known kernel.
- A case requiring multiple reduction tiles.
- A case using each supported precision mode.

The test should compare every result element, not just a checksum or aggregate total.

### 13.2 Retinal vessel segmentation

For application-level validation:
1. Freeze the CNN topology, trained weights, input size, preprocessing, padding, quantization, and output threshold.
2. Document the exact dataset split and preprocessing applied to DRIVE or any other chosen dataset.
3. Run the same test inputs through the software reference and the hardware-accurate model/RTL.
4. Compare intermediate tensors where practical, then compare final scores/masks.
5. Report the evaluation protocol and metrics.

Suggested metrics:
- **Dice/F1:** overlap between predicted and reference vessel masks.
- **Sensitivity/recall:** fraction of reference vessel pixels detected.
- **Specificity:** fraction of reference background pixels correctly rejected.
- **Pixel accuracy:** include cautiously because background pixels can dominate.
- **Numerical error:** max absolute error and mean absolute error for score/tensor comparisons.

Do not report application metrics until the output is produced by the specified RTL/software pipeline and compared with documented ground truth. If only a MAC/array testbench has been run, label the result as compute-unit verification, not retinal segmentation validation.

---

## 14. Synthesis and FPGA implementation checks

Simulation cannot establish BRAM/DSP inference, timing closure, or physical performance. For each implementation run, record:

- Exact FPGA part and board.
- Vivado version.
- RTL revision.
- Top module and source file list.
- Clock constraints and I/O constraints used.
- Synthesis and implementation completion status.
- LUT, flip-flop, DSP, BRAM/URAM counts.
- Achieved clock and worst timing slack.
- Critical path startpoint/endpoint and path type.
- High-fanout nets, congestion, and relevant warnings.
- Whether the bitstream was generated and whether physical validation was performed.

### Implementation checks
- Confirm the intended memory arrays infer BRAM.
- Confirm multipliers/accumulators map as expected.
- Inspect width-mismatch, truncation, inferred-latch, and unconstrained-path warnings.
- Check that all relevant clocks and I/O paths are constrained.
- Run timing analysis after implementation, not only synthesis.
- Do not equate a requested clock period with achieved operating frequency.
- Do not claim power or energy efficiency without a documented measurement/estimation method.

---

## 15. Regression strategy and sign-off

### Suggested development order

1. Compile/elaborate each module.
2. Pass reset/clock-enable tests.
3. Pass MAC arithmetic tests.
4. Pass PE tests.
5. Pass activation/weight/partial-sum routing tests.
6. Pass CNM BRAM and ping-pong tests.
7. Pass controller/scheduler tests.
8. Pass PE-array matrix/reference tests.
9. Pass integrated subsystem tests.
10. Run synthesis and inspect resource inference.
11. Run implementation and timing analysis.
12. Run software-reference/application evaluation.
13. Perform board validation if in scope.

Keep each stage's logs. Re-run all relevant lower-level tests after changes to shared interfaces, data widths, timing, or control semantics.

### Sign-off checklist

- [ ] All source files compile/elaborate with the documented tool.
- [ ] Every implemented module has a defined interface/behavior contract.
- [ ] MAC arithmetic passes directed and randomized reference tests.
- [ ] PE control, weight hold, and partial-sum behavior pass.
- [ ] PE-array output matches the reference for directed matrix/convolution cases.
- [ ] Synchronous BRAM data and valid timing are verified.
- [ ] Ping-pong ownership invariants pass directed and randomized tests.
- [ ] Partial-sum first/middle/last-tile behavior passes.
- [ ] Controllers pass delayed-response and timeout tests.
- [ ] Regression suite is reproducible from documented commands.
- [ ] Synthesis report confirms expected DSP/BRAM inference.
- [ ] Implementation timing is reviewed and critical paths documented.
- [ ] Application-level metrics are reported only if end-to-end evaluation exists.
- [ ] Hardware validation is reported only if the design was actually programmed and tested.

## 16. Results record template

Copy this table into each test report or maintain it in a CSV/Markdown regression summary.

| Field | Value |
|---|---|
| Test ID/name | TBD |
| DUT module / level | TBD |
| RTL revision | TBD |
| Simulator/tool version | TBD |
| Parameters / precision | TBD |
| Seed / vector count | TBD |
| Expected result | Defined by test/reference |
| Actual result | TBD |
| Pass/fail | Not run |
| Log / waveform | TBD |
| Notes / issue ID | TBD |

### FPGA implementation record

| Field | Value |
|---|---|
| FPGA part / board | TBD |
| Vivado version | TBD |
| Clock constraint | TBD |
| Achieved clock | TBD |
| LUT / FF / DSP / BRAM / URAM | TBD |
| Worst timing slack | TBD |
| Critical path | TBD |
| Bitstream generated | TBD |
| Physical board test | Not run / TBD |

## 17. Known specification dependencies

The following must be resolved before full sign-off:
- Exact MAC and accumulator widths and overflow semantics.
- Exact PE-array operand direction, pipeline latency, and output ordering.
- Exact BRAM read latency and same-address collision behavior.
- Exact ping-pong swap acceptance and simultaneous-event priority.
- Exact first/middle/last reduction-tile semantics.
- Supported precision modes and packed-weight bit layout.
- Exact CNN topology, dimensions, preprocessing, and quantization.
- Exact integrated top-level scope and FPGA part.

Until those contracts are fixed, tests should document the assumptions used rather than silently selecting behavior. A test that passes against an assumed contract is not proof that the architecture specification is complete.
