CROSSCOMPILE?=riscv64-unknown-elf-
CC=${CROSSCOMPILE}gcc
LD=${CROSSCOMPILE}ld
OBJCOPY=${CROSSCOMPILE}objcopy
OBJDUMP=${CROSSCOMPILE}objdump
BIN2HEX=./freedom_bin2hex
CFLAGS=-I. -O2 -march=rv64im  -Wall -mabi=lp64 -mexplicit-relocs  -mcmodel=medany 
CCASFLAGS=-I.  

LDFLAGS=-nostdlib -nostartfiles

all: umon.bin

elf: umon.elf

asm: umon.asm

umon.elf: umon.o umon.lds
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $(filter %.o,$^) -T$(filter %.lds,$^)

%.bin: %.elf
	$(OBJCOPY) -S -R .comment -R .note.gnu.build-id -O binary $^ $@
	$(BIN2HEX) -w 64 -i $@ -o $@.hex64
	$(BIN2HEX) -w 8 -i $@ -o $@.hex8
	$(OBJDUMP) -x -s -z -S -Dd $^ > $@.objdump

%.asm: %.elf
	$(OBJDUMP) -S $^ > $@

%.o: %.S
	$(CC) $(CFLAGS) $(CCASFLAGS) -c $< -o $@

clean:
	rm -f *.o
	rm -f *.elf
	rm -f *.bin
