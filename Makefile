.PHONY: all debug gdb clean

# Toolchain configuration
AS      = riscv64-unknown-elf-as
LD      = riscv64-unknown-elf-ld

# Assembly and linker flags
ASFLAGS = -g -march=rv32imczicsr -mabi=ilp32 -I src/
LDFLAGS = -m elf32lriscv -T src/linker.ld --compress-debug-sections=none

# Target binary and object files
TARGET = build/mini_os.elf
OBJS = build/mini_os.o build/user_a.o build/user_b.o

# 1. Normal run (builds the project and starts QEMU directly)
all: $(TARGET)
	qemu-system-riscv32 -machine sifive_e -nographic -kernel $(TARGET) -d in_asm,cpu

# 2. Debug run (starts QEMU in wait-for-gdb mode using -S -s)
debug: $(TARGET)
	qemu-system-riscv32 -machine sifive_e -nographic -kernel $(TARGET) -S -s

# Rule: Compile assembly source files (.s) into object files (.o)
build/%.o: src/%.s
	@mkdir -p build
	$(AS) $(ASFLAGS) $< -o $@

# Rule: Link object files into the final ELF executable
$(TARGET): $(OBJS) src/linker.ld
	@mkdir -p build
	$(LD) $(LDFLAGS) $(OBJS) -o $(TARGET)

# 3. Start GDB with the custom debug configuration
gdb:
	gdb-multiarch -x debug.gdb

# Clean up build artifacts
clean:
	rm -rf build/
