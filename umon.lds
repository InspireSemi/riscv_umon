OUTPUT_ARCH("riscv")
ENTRY(_start)

MEMORY {               
  sram (rwx) : ORIGIN = 0x0000, LENGTH = 0x4000
  maskrom_mem (rx) : ORIGIN = 0x20000000, LENGTH = 0x20000
}

SECTIONS
{

  .text ALIGN((ORIGIN(maskrom_mem) + 0x0), 64) : AT(ALIGN((ORIGIN(maskrom_mem) + 0x0), 64)) {
    PROVIDE(_ftext = .);
    *(.text.init)
    *(.text.unlikely .text.unlikely.*)
    *(.text .text.* .gnu.linkonce.t.*)
    PROVIDE(_etext = .);
    . += 0x40; /* to create a gap between .text and .data b/c ifetch can fetch ahead from .data */
  } 

}
