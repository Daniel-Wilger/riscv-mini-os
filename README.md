# RISC-V Mini-OS

A lightweight, bare-metal operating system built for the RISC-V architecture, featuring multiple user processes, a custom linker script, and an automated debugging workflow.

---

## Prerequisites

To build and run this project on Linux Mint, ensure you have the following toolchain installed:
- RISC-V GNU Toolchain (`riscv64-unknown-elf-as`, `riscv64-unknown-elf-ld`)
- QEMU (`qemu-system-riscv32`)
- GDB Multiarch (`gdb-multiarch`)

---

## Makefile Overview

The project uses an automated `Makefile` to handle assembly, linking, and simulation. Here are the available targets:

| Command | Description |
| :--- | :--- |
| `make` (or `make all`) | Compiles the source files, links the executable, and starts QEMU directly. |
| `make debug` | Compiles the project and starts QEMU in wait-for-gdb mode (`-S -s`). |
| `make gdb` | Launches `gdb-multiarch` and automatically loads `debug.gdb`. |
| `make clean` | Deletes the `build/` directory to ensure a fresh, clean build. |

---

## Build & Debug Workflow

Open **two terminal windows** in the project root to run the live debugging session:

1. **Terminal 1:** Start QEMU in debug mode:
   ```bash
   make debug
   ```
   *(To stop QEMU: press `Ctrl + A`, then `x`)*

2. **Terminal 2:** Start GDB:
   ```bash
   make gdb
   ```


## GDB Quick Reference

### 1. Execution Control

| Command | Shortcut | Description |
| :--- | :--- | :--- |
| `continue` | `c` | Resume program execution. |
| `stepi` | `si` | Execute exactly one assembly instruction (step into). |
| `nexti` | `ni` | Execute one instruction (step over function calls). |
| `monitor system_reset` | - | Reset the emulated QEMU CPU back to the start state. |
| `quit` | `q` | Exit GDB and disconnect from QEMU. |

> **Tip:** Press `Ctrl + C` in the GDB terminal to pause a running/looping OS instantly.

### 2. Bug & Trap Analysis (After a Crash / Trap)

| Command | Description |
| :--- | :--- |
| `info reg mcause` | Shows the reason for the trap (e.g., `8` = ecall, `2` = illegal instruction). |
| `info reg mepc` | Shows the memory address of the instruction that triggered the trap. |
| `x/1i $mepc` | Decodes and shows the exact assembly instruction that caused the crash. |
| `info registers` | Displays all standard CPU registers. |

### 3. Memory & String Inspection

| Command | Description |
| :--- | :--- |
| `x/s &shared_buffer` | Reads and prints the content of your IPC buffer as clear text. |
| `x/s $a1` | When inside a trap handler, shows the string address passed in register `a1`. |
| `x/5i $pc` | Shows the next 5 assembly instructions starting from the current PC. |
| `disas <label>` | Disassembles the complete assembly code of a specific label/function. |

### 4. GDB Visual TUI Modes

| Command | Description |
| :--- | :--- |
| `layout asm` | Splits the screen to show live assembly and current PC position. |
| `layout regs` | Splits the screen to show live registers (highlighting changes in red). |
| `Ctrl + X, then A` | Toggles the split-screen TUI mode on/off if the display gets distorted. |