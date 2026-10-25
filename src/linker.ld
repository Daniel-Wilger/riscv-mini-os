ENTRY(_start)       /* start-address from the program */

MEMORY
{
    FLASH (rx)  : ORIGIN = 0x20400000, LENGTH = 128K
    RAM   (rwx) : ORIGIN = 0x80000000, LENGTH = 16K
}

SECTIONS
{
    .text : { *(.text*) } > FLASH
    .data : { *(.data*) } > RAM
    .bss  : { *(.bss*) }  > RAM

/* Stacks */
  _machine_stack_size = 2K;
  _machine_stack_top  = ORIGIN(RAM) + LENGTH(RAM);
  
  _user_a_stack_size  = 2K;
  _user_a_stack_top   = _machine_stack_top - _machine_stack_size;
  
  _user_b_stack_size  = 2K;
  _user_b_stack_top   = _user_a_stack_top - _user_a_stack_size;
}
