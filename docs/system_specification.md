# System Specification — FPGA-Based NPU for Retinal Vessel Segmentation

**Status:** Working design specification  
**Implementation status:** Architecture and module concepts are documented; each feature must be marked implemented only after checking the current RTL and verification evidence.  
**Primary workload:** CNN-based retinal vessel segmentation, with DRIVE intended as the evaluation dataset.

## 1. Purpose and scope

This document defines the intended system-level organization of the FPGA-based neural processing unit (NPU). The system is intended to accept image/tensor data, prepare it for CNN computation, execute tiled operations on a 4×4 processing-element (PE) array, manage local memory and partial sums, and format segmentation results.

This is a design target, not proof that every listed subsystem is already integrated or validated. The current repository should be used as the authority for which modules exist and what interfaces they actually implement.

## 2. Design goals

1. Provide a modular SystemVerilog architecture suitable for simulation and FPGA implementation.
2. Use a 4×4 systolic PE array as the initial compute engine.
3. Support parameterized arithmetic blocks and explicit control of data movement.
4. Reduce repeated off-chip traffic through activation/weight reuse and local BRAM storage.
5. Overlap data loading and computation where the memory and controller interfaces permit it.
6. Support the end application of retinal vessel segmentation.
7. Collect reproducible correctness, latency, throughput, utilization, and FPGA resource measurements.

## 3. System-level data path

```text
Host / External Memory
        |
        v
Input Interface (AXI4-Lite control + AXI4-Stream data, as implemented)
        |
        v
Image Frontend
(frame/coordinates, ROI, format conversion, normalization,
 optional filtering, tensor formatting)
        |
        v
DMA / Activation and Weight Buffers
        |
        v
Ping-Pong Buffers <----> CNM BRAM Banks
        |                         |
        +------------+------------+
                     v
             Memory Scheduler
                     |
                     v
          4 x 4 Systolic PE Array
          (16 Processing Elements)
                     |
                     v
          Reduction / Accumulation
                     |
                     v
          CNN Operators
  (bias, activation, pooling, scaling,
          quantization as supported)
                     |
                     v
       Segmentation Formatter / Score
                     |
                     v
           Threshold / Vessel Mask
                     |
                     v
              Output Buffer
                     |
                     v
             Output Interface
```

The diagram describes the proposed system organization. Actual RTL connectivity, AXI protocol completeness, and operator availability must be confirmed from source code and tests.

## 4. Top-level subsystem responsibilities

| Subsystem | Intended responsibility | Important inputs | Important outputs / status |
|---|---|---|---|
| Clock and reset | Establish synchronous operation and reset state | Clock, reset | Clocked state and reset behavior |
| AXI4-Lite/register bank | Configure operation and expose status | Register reads/writes | Configuration, status, interrupt |
| AXI4-Stream input/output | Stream image/tensor data and results | Stream payload and handshake | Accepted input / output stream |
| Image frontend | Prepare pixels and format tensors/windows | Input pixels, dimensions, configuration | Normalized/formatted activation data |
| DMA / source buffers | Move or stage activations and weights | External-memory transfers or local writes | Buffer contents and ready status |
| Ping-pong controller | Manage active and inactive tile buffers | Load, consumed, swap events | Active-bank selection and ready/load enables |
| CNM BRAM banks | Provide local activation and weight bandwidth | Read/write enables, addresses, data | Synchronous read data and valid |
| Memory scheduler | Sequence tile reads and compute launch | Tile-ready and read-valid events | Read requests, compute-start, busy/done |
| PE controller / tile controller | Coordinate array activity and tile progression | Start, dimensions, completion | PE enables, tile transitions |
| 4×4 PE array | Perform multiply-accumulate operations | Activation, weight, partial-sum/control | PE or column partial sums |
| Reduction/accumulation | Combine partial sums across the required reduction dimensions | PE results, accumulation controls | Accumulated result and valid |
| CNN operators | Apply supported post-MAC transformations | Accumulator result and layer config | Transformed feature values |
| Retinal output | Convert model outputs into scores/mask | Scores, threshold | Vessel mask/output stream |
| Performance/debug | Measure behavior and expose faults | Events and counters | Counters, status, debug signals |

A listed block may be planned or partially implemented. Do not describe it as completed until source, integration, and verification evidence agree.

## 5. Control and configuration

The design notes identify a register interface with configuration fields including image width/height, layer count, precision selection, activation selection, threshold, performance data, status, and interrupt enable. The exact address map, reset values, write strobes, and software-visible semantics must be taken from the current register-bank RTL and documented here once frozen.

The intended control hierarchy is:

```text
Main FSM
 ├── Layer Controller
 ├── Tile Controller
 ├── Dataflow Controller
 ├── Memory Scheduler
 └── PE Controller
```

- **Main FSM:** system-level sequencing and completion/error handling.
- **Layer controller:** layer configuration and layer progression.
- **Tile controller:** iteration over input/output/reduction tiles.
- **Dataflow controller:** activation/weight movement order and dataflow-related control.
- **Memory scheduler:** requests local memory reads and launches computation after required data is ready.
- **PE controller:** controls PE-array execution and drain/finish behavior.

These responsibilities overlap conceptually; define one owner for each state transition and handshake to avoid multiple controllers independently advancing the same operation.

## 6. Compute contract

The baseline compute organization is a 4×4 array, i.e. 16 PEs. If every PE can retire one MAC per clock and all PEs are active, the nominal arithmetic ceiling is:

\[
\text{MACs/cycle}_{\max}=4\times4=16
\]

This is a theoretical peak, not measured throughput. It excludes fill/drain cycles, stalls, unavailable operands, memory waits, operator latency, and reduced utilization for shapes that do not map cleanly to the array.

The arithmetic contract must specify:
- Activation and weight signedness and bit widths.
- Product width and accumulator width.
- Whether accumulation wraps, saturates, or is widened.
- How partial sums are initialized and accumulated across K/reduction tiles.
- Supported precision modes and their exact packing/sign-extension rules.
- Result-valid timing and any pipeline latency.
- Behavior on reset, disabled clock enable, abort, and malformed commands.

These details must be consistent between the RTL, reference model, and testbench.

## 7. Memory and dataflow contract

The intended memory path is:

`External memory → DMA → activation/weight buffers → ping-pong buffers → CNM BRAM banks → PE array`

The intended dataflow is weight-stationary at the PE-array level: weights are loaded into PE-local registers and reused while activations are streamed through the array. The exact temporal schedule, whether weights remain stationary for a full output tile or a smaller segment, and how partial sums move must be documented from the implemented PE and routing logic.

Memory read latency matters. For synchronous BRAM, read addresses/enables are sampled at a clock edge and read data is available according to the inferred/implemented pipeline. The scheduler must align data-valid signals with the corresponding address and control metadata.

## 8. Image-processing and model boundary

The target workload is retinal vessel segmentation. The planned high-level path is:

`Retinal image → preprocessing → CNN feature extraction/convolution → activation/feature processing → segmentation scores → thresholding → binary vessel mask`

The frontend may include grayscale/format conversion, normalization, optional filtering, ROI handling, coordinate generation, and tensor formatting. Do not assume all of these are implemented in RTL. The model topology, trained weights, input resolution, channel counts, padding, stride, pooling, activation, and quantization parameters must be frozen before end-to-end evaluation.

The design notes have referenced other image-classification workloads in older material. This repository's primary application should remain retinal vessel segmentation unless the project scope is deliberately changed and documented.

## 9. Verification requirements

At minimum, create self-checking tests for:
- Reset and clock-enable behavior.
- Register read/write and AXI handshake behavior, if those interfaces are in scope.
- Frontend coordinate, boundary, padding, and tensor formatting behavior.
- Buffer ownership and ping-pong swaps, including backpressure.
- BRAM read latency, address mapping, and valid alignment.
- MAC signed arithmetic, width/overflow behavior, and accumulation.
- PE-array fill, steady-state, drain, and tile-boundary behavior.
- Partial-sum initialization and multi-tile accumulation.
- Scheduler progress under delayed memory responses.
- End-to-end output comparison against a software reference.

Testbenches should fail automatically on mismatch and print reproducible configuration/seed information.

## 10. Performance and quality metrics

Report measured values with the exact RTL revision, FPGA part, tool version, clock constraint, precision mode, and workload shape.

| Metric | Definition / reporting guidance |
|---|---|
| Functional correctness | Mismatch count against an independent reference |
| Cycle count | Clearly define start and end events |
| Latency | Cycles divided by achieved clock frequency; separate compute-only and end-to-end |
| MAC throughput | Completed MACs/s, not only theoretical MAC/cycle |
| PE utilization | Active useful PE-cycles divided by available PE-cycles |
| Stall cycles | Separate memory, dependency, control, and backpressure stalls if possible |
| Memory traffic | Read/write transactions and bytes by memory level |
| FPGA resources | LUT, FF, DSP, BRAM/URAM from the selected Vivado report |
| Timing | Achieved clock, worst negative slack / timing slack, and critical path |
| Segmentation quality | Dice/F1, sensitivity/recall, specificity, and any other stated metric with evaluation protocol |

No numerical performance result is asserted by this specification.

## 11. FPGA implementation assumptions and unknowns

- **RTL:** SystemVerilog is the stated design language.
- **Tool:** AMD Xilinx Vivado is the stated implementation tool.
- **Device/board:** the exact part and board revision must be confirmed before pin constraints or resource claims are made. Do not assume a specific Zynq part from prior unrelated board exercises.
- **Clock:** target frequency and timing constraints are not frozen in this document.
- **Memory inference:** BRAM mapping must be verified in synthesis reports; behavioral arrays alone do not prove BRAM inference.
- **Interfaces:** AXI compliance and clock-domain assumptions require interface-level verification.

## 12. Risks and open decisions

1. Freeze numeric formats, accumulator width, overflow policy, and supported precision modes.
2. Freeze the CNN topology and tensor dimensions used for evaluation.
3. Verify that dataflow control and PE scheduling implement the stated weight-stationary behavior.
4. Define a precise handshake protocol between DMA, ping-pong buffers, CNM banks, scheduler, and PE array.
5. Define error/timeout behavior when a tile never becomes ready.
6. Confirm whether pooling, scaling, quantization, and output thresholding exist in RTL or remain software-side.
7. Confirm the exact FPGA device, clock, and external-memory interface.
8. Add reproducible synthesis/implementation and end-to-end evaluation evidence.

## 13. Status vocabulary

Use these terms consistently:
- **Planned:** documented intent; RTL may not exist.
- **Implemented:** RTL exists and compiles.
- **Unit-tested:** self-checking unit tests pass.
- **Integrated:** connected in the intended top-level hierarchy.
- **System-verified:** integration tests pass against expected behavior.
- **Synthesized:** a successful synthesis report exists for a named device.
- **Implemented on FPGA:** implementation/bitstream exists for a named device.
- **Hardware-validated:** physical test evidence exists.
- **Application-validated:** segmentation output has been evaluated against a documented reference.

A successful compile or synthesis is not evidence of application-level accuracy or hardware performance.
