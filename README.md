# FPGA-Based NPU for Retinal Vessel Segmentation

**SystemVerilog | AMD Xilinx Vivado | Zynq-7000 FPGA | CNN Acceleration**

An FPGA-oriented Neural Processing Unit (NPU) designed to accelerate convolutional neural network (CNN) workloads for retinal vessel segmentation. The project explores a parameterized compute architecture, a 4×4 weight-stationary systolic processing-element (PE) array, distributed Compute-Near-Memory (CNM) BRAM buffers, ping-pong buffering, and parallel reduction and accumulation.

> **Project status:** Work in progress. Refer to the implementation and verification status below for the functionality currently available. Architectural goals and planned features are distinguished from demonstrated results.

## Table of Contents

- [Overview](#overview)
- [Objectives](#objectives)
- [Architecture](#architecture)
- [Dataflow and Memory Organization](#dataflow-and-memory-organization)
- [Repository Structure](#repository-structure)
- [Hardware and Software](#hardware-and-software)
- [Verification and Evaluation](#verification-and-evaluation)
- [FPGA Implementation](#fpga-implementation)
- [Getting Started](#getting-started)
- [Dataset and Retinal Vessel Segmentation](#dataset-and-retinal-vessel-segmentation)
- [Implementation Status](#implementation-status)
- [Research Directions](#research-directions)
- [Limitations](#limitations)
- [References](#references)
- [License](#license)

## Overview

Retinal vessel segmentation identifies blood vessels in retinal fundus images and produces a vessel mask that can support subsequent medical-image analysis.

CNN-based segmentation involves repeated convolution, multiplication, accumulation, nonlinear activation, and intermediate feature-map transfers. Executing these operations efficiently on an FPGA requires coordinated design of the compute datapath, memory hierarchy, dataflow, and control logic.

This project investigates an FPGA-oriented NPU architecture intended to address these challenges using:

- A **4×4 systolic PE array** for parallel multiply-accumulate computation.
- **Parameterized MAC units** to support configurable datapath dimensions and arithmetic widths where implemented.
- **Weight-stationary dataflow** to retain weights within processing elements during the relevant computation schedule.
- **Distributed CNM BRAM banks** to organize activation and weight delivery close to the compute array.
- **Ping-pong buffering** to enable overlap between data loading and computation when the control and memory interfaces support concurrent operation.
- **Parallel reduction and accumulation** for combining partial results.
- A modular control hierarchy for coordinating layers, tiles, memory transfers, and PE execution.

The design is being developed in SystemVerilog with AMD Xilinx Vivado as the FPGA implementation environment.

## Objectives

1. Design a modular, parameterized RTL architecture for an FPGA-based NPU.
2. Develop and verify the MAC datapath, processing elements, and 4×4 systolic array.
3. Organize activation, weight, and partial-sum storage using BRAM-oriented memory structures.
4. Implement control and scheduling mechanisms for tiled computation and data movement.
5. Build a verification environment that compares RTL outputs against software reference calculations.
6. Evaluate computational throughput, latency, resource utilization, and memory-related performance.
7. Progress toward retinal vessel segmentation using the DRIVE dataset and a software-to-hardware validation workflow.

## Architecture

The intended system-level processing path is:

```text
Retinal Image / Input Pixel Stream
                 |
                 v
       System Input Interface
                 |
                 v
          Image Frontend
                 |
                 v
       Activation / Weight Storage
                 |
                 v
       CNM BRAM Banks and Routing
                 |
                 v
        +---------------------+
        |  4 x 4 PE Array     |
        |                     |
        |  16 Processing      |
        |  Elements           |
        +---------------------+
                 |
                 v
       Reduction / Accumulation
                 |
                 v
       CNN Operators and Output
                 |
                 v
       Retinal Vessel Mask
```

This diagram describes the intended architecture; it does not imply that the entire end-to-end path is already integrated.

### Processing element

Each PE is intended to contain the datapath and state required for multiplication and accumulation, including activation and weight inputs, local registers, accumulator state, and control signals.

The 4×4 array provides 16 processing elements. Under a one-MAC-per-PE-per-cycle operating schedule, the array has a nominal peak of 16 MAC operations per active cycle. Actual throughput depends on the implemented arithmetic pipeline, clock frequency, data availability, array utilization, and scheduling overhead.

### Compute architecture

The compute subsystem is intended to support:

- Parameterized signed or unsigned arithmetic as specified by the implemented MAC interface.
- Local weight storage and controlled activation delivery.
- Partial-sum management and result forwarding.
- Array-level control for loading weights, enabling computation, and accumulating results.

Arithmetic precision, overflow behavior, pipeline latency, and supported configurations must be documented against the actual RTL.

### Control architecture

The planned control hierarchy includes:

- Main FSM
- Layer controller
- Tile controller
- Dataflow controller
- Memory scheduler
- PE controller

These modules coordinate execution state, data availability, tile boundaries, accumulation control, and completion signaling.

## Dataflow and Memory Organization

### Weight-stationary dataflow

In weight-stationary execution, weights remain local to their assigned processing elements while multiple activations are processed against them. This can reduce repeated weight transfers and improve reuse.

The activation path supplies input data to the array, while partial sums are accumulated and transferred according to the implemented PE interconnect and scheduling scheme.

The exact data movement, inter-PE forwarding, and accumulation timing are defined by the RTL and should be verified through cycle-level simulation.

### Compute-Near-Memory (CNM)

The memory architecture is intended to organize storage around the needs of the compute array:

- **Activation buffers:** Store input or intermediate activation tiles.
- **Weight buffers:** Store convolution weights before or during PE execution.
- **CNM BRAM banks:** Provide banked activation and weight data paths.
- **Partial-sum buffers:** Retain intermediate accumulation results.
- **Ping-pong buffers:** Maintain separate storage banks for active computation and next-tile loading.

The target data path is:

```text
External Data Source
        |
        v
  DMA / Data Loading
        |
        v
Activation and Weight Buffers
        |
        v
  Ping-Pong Buffer Banks
        |
        v
     CNM BRAM
        |
        v
      PE Array
        |
        v
 Partial-Sum Storage
        |
        v
   Final Results
```

The purpose of ping-pong buffering is to overlap transfers and computation. The actual speedup depends on whether the implementation can sustain concurrent memory operations and whether the controller prevents bank conflicts, starvation, and premature buffer swaps.

## Repository Structure

```text
rtl/             SystemVerilog design modules
  common/        Clock, reset, and shared logic
  interfaces/    AXI and system interfaces
  frontend/      Image-processing frontend
  compute/       MAC, PE, array, and reduction logic
  memory/        BRAM buffers and memory control
  control/       FSMs and execution scheduling
  operators/     CNN operator implementations
  output/        Segmentation and output processing
  top/           Top-level integration

sim/             Unit, integration, and system testbenches
software/        Python reference models and evaluation tools
docs/            Architecture, specifications, and design notes
scripts/vivado/  Vivado automation scripts
constraints/     FPGA pin and timing constraints
datasets/        Dataset setup and access instructions
results/         Curated simulation and implementation results
```

Only directories and modules that exist should be treated as implemented.

## Hardware and Software

| Component | Target or purpose |
|---|---|
| RTL language | SystemVerilog |
| FPGA development environment | AMD Xilinx Vivado |
| FPGA board | Zybo Z7-10, if confirmed for this design |
| FPGA device | Zynq-7000 family; record the exact part and package from the Vivado project |
| Compute organization | 4×4 systolic PE array |
| Dataflow | Weight-stationary |
| On-chip storage | BRAM-oriented activation, weight, and partial-sum buffers |
| Software verification | Python reference calculations and image evaluation |
| Dataset | DRIVE retinal vessel segmentation dataset |

Actual clock constraints, arithmetic precision, resource usage, and tool versions should be recorded from the implementation environment.

## Verification and Evaluation

The verification strategy is intended to cover several levels.

### 1. Unit-level verification

Verify the MAC units, processing elements, buffer interfaces, controllers, and arithmetic operations independently.

### 2. Array-level verification

Use known activation and weight matrices to check the 4×4 array against a software reference. Check result correctness, valid timing, reset behavior, and accumulation across successive tiles.

### 3. Memory and control verification

Test BRAM read latency, simultaneous loading and computation where supported, buffer swaps, partial-sum retention, stalls, reset recovery, and tile-completion signaling.

### 4. Integrated simulation

Run representative matrix multiplication or convolution workloads through the integrated compute and memory path. Record expected outputs, observed outputs, cycle counts, and any mismatches.

### 5. Application-level validation

Compare software reference results with the results produced by the hardware model. Evaluate segmentation quality only after the relevant network, weights, preprocessing, and output conversion are implemented.

### Metrics to report

- Functional correctness and numerical error
- Cycles per tile and per image
- Sustained MAC throughput
- PE utilization and stall cycles
- BRAM, LUT, flip-flop, and DSP utilization
- Post-implementation clock frequency and timing slack
- End-to-end latency and throughput
- Segmentation metrics, such as sensitivity, specificity, and Dice score, where appropriate

No performance or segmentation results should be reported until they have been measured and their methodology documented.

## FPGA Implementation

The intended implementation flow is:

1. Add RTL sources and simulation testbenches.
2. Elaborate and synthesize the design.
3. Resolve width, inference, and connectivity issues.
4. Apply the correct board constraints.
5. Run implementation, placement, and routing.
6. Review timing reports and resource utilization.
7. Generate the bitstream when the design is ready.
8. Validate hardware behavior using suitable board interfaces and debug instrumentation.

Record the exact FPGA part, Vivado version, clock constraints, resource reports, and timing results for reproducibility.

## Getting Started

### Prerequisites

- AMD Xilinx Vivado compatible with the target FPGA.
- A SystemVerilog simulator, such as Icarus Verilog for supported constructs or Vivado Simulator.
- Python and the dependencies specified in the software environment file, once provided.
- The RTL sources and any required initialization files.

### Clone the repository

```bash
git clone https://github.com/<YOUR_USERNAME>/fpga-npu-retinal-vessel-segmentation.git
cd fpga-npu-retinal-vessel-segmentation
```

Replace `<YOUR_USERNAME>` with your GitHub username.

### Simulation

Use the testbench and file list for the specific module or test you want to verify. Add exact simulator commands to this section after the corresponding testbench is checked and runnable.

### Vivado

Open the Vivado project or run the documented Tcl setup script when available. Confirm the target FPGA part, source files, initialization files, and XDC constraints before synthesis.

## Dataset and Retinal Vessel Segmentation

The DRIVE dataset is intended for application-level evaluation of retinal vessel segmentation.

The software workflow should document:

1. Dataset acquisition and directory layout.
2. Image loading and preprocessing.
3. Reference model architecture and trained weights.
4. Numerical precision and quantization rules.
5. Hardware input and output tensor formats.
6. Comparison of software and hardware predictions.
7. Segmentation metrics and evaluation methodology.

Dataset files are not included by default. Follow the dataset provider's access and usage conditions, and document how to obtain the data.

## Implementation Status

Maintain this table as the project progresses.

| Milestone | Status |
|---|---|
| Architectural specification | Documented in project design files |
| Modular RTL development | In progress; track modules individually |
| MAC and PE unit verification | Record after test execution |
| 4×4 array verification | Record after reference comparison |
| Memory and controller integration | Record after integration testing |
| Complete NPU top-level | Planned until integrated and verified |
| Vivado synthesis and timing analysis | Record using actual reports |
| FPGA hardware validation | Record after board testing |
| DRIVE segmentation evaluation | Planned until end-to-end evaluation is complete |

## Research Directions

Potential investigation areas include:

- Precision versus resource utilization for low-bit-width arithmetic.
- Weight-stationary data reuse and PE utilization.
- Ping-pong buffering and memory-transfer overlap.
- BRAM banking and sustained activation bandwidth.
- Partial-sum accumulation latency and buffering requirements.
- Resource-efficient scheduling and stall reduction.
- Hardware/software numerical agreement for retinal vessel segmentation.

Each investigation should include a baseline, a clearly defined architectural change, reproducible measurements, and an analysis of the trade-offs.

## Limitations

This project is a work in progress. Proposed architectural features must not be confused with fully integrated functionality or measured performance. Resource utilization, maximum operating frequency, power consumption, and segmentation quality will be reported only when supported by implementation or experimental evidence.

## References

- DRIVE: Digital Retinal Images for Vessel Extraction. Dataset and associated publication information should be cited here.
- AMD Vivado Design Suite documentation: https://docs.amd.com/
- Additional NPU architecture papers and design references will be listed as they are incorporated into the implementation.

## License

See [LICENSE](LICENSE) for the terms governing the use, modification, and distribution of this repository.
