.section .text
.globl user_b_code
.include "macros.inc"
.include "config.inc"
.include "constants.inc"

user_b_code: 
# user buffer initialisieren
la t0, buffer_remaining_length
li t1, USER_BUFFER_LENGTH
sw t1, 0(t0)
# IPC
li a0, IPC_FD            # fd = 3 
la a1, buffer       # a1 = Adresse des Buffers buffer
la t0, buffer_remaining_length
lw a2, 0(t0)        # a2 = buffer_remianing_length
li a7, SYS_CALL_RECEIVE           # RECEIVE-Ecall
ecall 
sw a2, 0(t0)        # update buffer_remaining length
li a7, SYS_CALL_EXIT           # EXIT-Ecall
addi s11, x0, -1
ecall
jal x0, USER_B_ERROR

USER_B_ERROR:
jal x0, USER_B_ERROR

.section .bss
buffer:
    .space 32
buffer_remaining_length: 
    .space 4
