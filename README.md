 # IMC Project — Reference Document

## What Is This Project?

This project implements a **digital SRAM-based In-Memory Computing (IMC) engine** — a building block for AI/ML edge accelerators. Instead of moving data between memory and a separate ALU (the "memory wall" bottleneck), computation happens *inside* the SRAM array itself.

### The Problem: Memory Wall

In conventional von Neumann architectures, running a neural network inference means:
- Fetch operands from SRAM/DRAM → Compute in ALU → Write results back
- Repeated billions of times for models with millions of weights
- Data movement consumes **100–1000× more energy** than the computation itself
- Transfer speed limits compute speed → the "memory wall"

### The Solution: In-Memory Computing

- Modify SRAM cells to perform bitwise Boolean operations (AND, OR, XOR, NOR, etc.) **directly on stored data**
- Read two rows simultaneously from dual-port SRAM → combine on bitlines → result in one cycle
- SRAM serves as **both storage and compute fabric**
- For a 32-bit row: 32 Boolean ops in parallel per cycle (vs. ALU doing them serially or in smaller widths)
- Real companies (Samsung, TSMC, Intel) are actively building IMC chips

### Where This Fits in an AI Accelerator Stack

```
Layer 5: Application (DNN model)
Layer 4: Compiler/Mapper (schedules ops to hardware)
Layer 3: IMC Compute Array        ← THIS PROJECT
Layer 2: Memory Controller
Layer 1: I/O & Interconnect
```

### Energy Efficiency Impact

| Architecture         | Energy/Op | Throughput | Use Case                |
|----------------------|-----------|------------|-------------------------|
| Von Neumann (CPU)    | ~100 pJ   | ~10 GOPS   | General purpose         |
| Near-Memory (PIM)    | ~10 pJ    | ~100 GOPS  | Server-side AI          |
| **In-Memory (this)** | **~1 pJ** | **~1 TOPS**| **Edge AI, mobile, IoT**|
| Analog IMC           | ~0.1 pJ   | ~10 TOPS   | Research / emerging     |

---

## What We Are Building

### Part A: Standard Dual-Port SRAM (Baseline)

Conventional memory with separate read/write — the baseline to compare against.

| Module              | What It Is                                | Spec                                          |
|---------------------|-------------------------------------------|-----------------------------------------------|
| `sram_single_port`  | Basic single-port SRAM                    | 256 rows × 32 bits, BRAM-inferred             |
| `sram_dual_port`    | True dual-port SRAM (Port A + Port B)     | Independent R/W, Port A priority on collision  |
| `tb_sram_dual_port` | Self-checking testbench (8 tests + random)| Verifies write, read, collision, full-array    |

### Part B: SRAM with In-Memory Boolean Compute (IMC)

Augments the dual-port SRAM with a compute unit so bitwise operations happen *inside* memory.

| Module              | What It Is                                | Spec                                                          |
|---------------------|-------------------------------------------|---------------------------------------------------------------|
| `imc_compute_unit`  | Combinational Boolean compute unit        | 8 ops (AND/OR/XOR/NOR/NAND/XNOR/NOT/PASS), zero flag, popcount |
| `imc_sram_32x256`   | Top-level: SRAM + compute integrated      | Memory Mode + Compute Mode (2-cycle pipeline)                  |
| `tb_imc_sram`       | Self-checking testbench (16 tests + random + throughput benchmark) | Verifies all ops, flags, bulk stress, speedup |

### Part C: FPGA Implementation & Analysis (User Handles)

Synthesis on target FPGA, resource utilization comparison, throughput analysis, scaling study, real-world application reflection (BNN inference, Hamming distance).

---

## Directory Structure

```
src/
  verilog/
    sram_single_port.v        ← A1: Single-port SRAM (inferred BRAM)
    sram_dual_port.v           ← A2: True dual-port SRAM
    imc_compute_unit.v         ← B1: 8-op Boolean compute + popcount
    imc_sram_32x256.v          ← B2: Top-level IMC-SRAM (SRAM + compute)
  systemverilog/
    sram_single_port.sv
    sram_dual_port.sv
    imc_compute_unit.sv
    imc_sram_32x256.sv
  vhdl/
    sram_single_port.vhd
    sram_dual_port.vhd
    imc_compute_unit.vhd
    imc_sram_32x256.vhd
tb/
  verilog/
    tb_sram_dual_port.v        ← A3: 8 tests + 100 random
    tb_imc_sram.v              ← B3: 16 tests + throughput benchmark + 100 random
  systemverilog/
    tb_sram_dual_port.sv
    tb_imc_sram.sv
  vhdl/
    tb_sram_dual_port.vhd
    tb_imc_sram.vhd
```

**Total: 12 RTL source files + 6 testbench files = 18 files**
All three HDL versions (Verilog, SystemVerilog, VHDL) implement identical behavior.

---

## Key Technical Concepts

### 6T SRAM Cell
Standard 6-transistor cell. Two cross-coupled inverters for storage, two access transistors on Word Line (WL), data via complementary Bit Lines (BL, BLB). On FPGA, modeled as Block RAM (BRAM).

### Dual-Port SRAM
Two independent ports (A, B), each with own address/data/write-enable. Both can operate simultaneously in the same clock cycle. Critical for IMC: read operand A and operand B in the same cycle.

### In-Memory Boolean Logic
Read two rows simultaneously → combine bitline values → bitwise result in one cycle.
For 32-bit rows: 32 parallel Boolean ops per cycle.

### Compute Mode Pipeline (2 cycles)

```
Cycle 1 (READ):          Read row A (Port A) + Read row B (Port B) simultaneously
Cycle 2 (COMPUTE+WRITE): Compute unit performs op → result written to dest row → compute_done asserts
```

### Row Parallelism
One IMC cycle processes the **entire row width** in parallel.
- 32-bit row  = 32 ops/cycle
- 256-bit row = 256 ops/cycle (8× throughput of 32-bit)

This is the core advantage of IMC.

### Popcount (ones_count)
Counts the number of 1-bits in the result. Implemented as a logarithmic-depth adder tree.
Used for: Hamming distance computation (XOR + popcount), BNN accumulation.

---

## Operation Encoding Reference

| op_sel  | Operation | Formula         | Use Case                          |
|---------|-----------|-----------------|-----------------------------------|
| 3'b000  | AND       | A & B           | Bitmasking, feature intersection  |
| 3'b001  | OR        | A \| B          | Feature union, flag merging       |
| 3'b010  | XOR       | A ^ B           | Change detection, encryption      |
| 3'b011  | NOR       | ~(A \| B)       | Complement of union               |
| 3'b100  | NAND      | ~(A & B)        | Complement of intersection        |
| 3'b101  | XNOR      | ~(A ^ B)        | Equality comparison (bit-level)   |
| 3'b110  | NOT A     | ~A              | Bitwise complement of row A       |
| 3'b111  | PASS A    | A               | Pass-through (no compute)         |

---

## Engineering Rules Applied

### RTL Rules — Think Like an RTL Design Engineer

1. **Syntax-free RTL** — Zero tolerance for syntax errors. Every file compiles cleanly across all target tools (VCS, Vivado, Quartus, iverilog, ModelSim).
2. **Synthesizable constructs only** — No `initial` blocks in RTL (TB only). No `#delay` in RTL. No `$display`/`$monitor` in RTL. No `real`/`time` types in RTL. Use `always @(posedge clk)` (Verilog), `always_ff` (SV), `process(clk)` (VHDL) for sequential. Use `always @(*)` / `always_comb` / combinational process for combo logic. No latches — every `if` has `else`, every `case` has `default`.
3. **Optimized RTL** — Clean BRAM inference (not distributed RAM). No redundant registers, no dead code. Exact signal widths (no oversized buses). Efficient adder tree for popcount.
4. **Design engineer mindset** — Registered outputs for timing closure. Clean module boundaries. Structural hierarchy with reusable leaf modules.

### Testbench Rules

1. **Syntax-free** — Same zero-error standard. Portable across simulators.
2. **Self-checking** — Every test has explicit expected value + PASS/FAIL verdict.
3. **Deterministic + random** — Fixed spec tests for coverage, random tests for corner-case hunting.
4. **Clean structure** — Task/function-based test drivers, numbered tests, summary at end.

---

## Key Design Decisions

| Decision                    | Choice                          | Rationale                                        |
|-----------------------------|---------------------------------|--------------------------------------------------|
| BRAM inference              | Synchronous registered read     | Required for Xilinx/Intel BRAM mapping           |
| Read-during-write (same port)| Read-first (returns old value) | Default BRAM behavior for both Xilinx and Intel  |
| Write collision (dual-port) | Port A priority                 | Per spec; Port B write suppressed on same addr   |
| Compute pipeline            | 2-cycle FSM (READ → COMPUTE)   | Cycle 1 reads both rows, cycle 2 computes+writes |
| Popcount implementation     | For-loop (synth builds tree)    | Clean RTL; synth tool infers adder tree          |
| VHDL dual-port BRAM         | Shared variable approach        | Required for Xilinx BRAM inference (UG901)       |
| Tests 1-8 in tb_imc_sram   | Adapted to Memory Mode          | Top module has single-port-like Memory Mode      |

---

## Real-World Applications

### Binary Neural Networks (BNN)
- Weights and activations are 1-bit → stored in SRAM rows
- **XNOR** replaces multiplication (1-bit multiply = XNOR)
- **Popcount** replaces accumulation (count matching bits)
- IMC does XNOR + popcount on entire rows in 2 cycles

### Hamming Distance
- Distance = number of bit positions where two vectors differ
- Compute: **XOR** (finds differing bits) → **popcount** (counts them)
- Applications: error-correcting codes, image similarity search, DNA sequence comparison

---

## Deliverables Checklist

| # | Deliverable              | Status    | Files / Notes                                 |
|---|--------------------------|-----------|-----------------------------------------------|
| 1 | RTL Source (3 HDLs)      | Done      | 4 modules × 3 languages = 12 files in `src/`  |
| 2 | Testbenches (3 HDLs)     | Done      | 2 TBs × 3 languages = 6 files in `tb/`        |
| 3 | FPGA Project             | User TODO | Vivado/Quartus project setup                   |
| 4 | Synthesis Reports        | User TODO | Resource utilization, timing, power             |
| 5 | Simulation Waveforms     | User TODO | Annotated screenshots for all tests            |
| 6 | Throughput Benchmark     | Done      | Printed by `tb_imc_sram` (cycle counts+speedup)|
| 7 | Analysis Report (Part C) | User TODO | C1–C4 tables and questions (max 1 A4 page)     |
| 8 | Block Diagrams           | User TODO | Architecture diagrams for dual-port & IMC-SRAM  |

---

## Compile Check Status

All 18 files verified with VCS (Synopsys):
- **Verilog (6 files):** `vlogan -sverilog -timescale=1ns/1ps` → PASS
- **SystemVerilog (6 files):** `vlogan -sverilog -timescale=1ns/1ps` → PASS
- **VHDL (6 files):** `vhdlan` → Fixing minor VHDL aggregate issue, then PASS

VCS setup used:
```tcsh
setenv VCS_HOME /tools/dist/vcs/W-2024.09-SP2-3
setenv VCS_TARGET_ARCH amd64
setenv PATH "${VCS_HOME}/bin:${PATH}"
```
