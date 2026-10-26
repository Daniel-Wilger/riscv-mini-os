.section .text
.globl user_a_code   
.include "macros.inc"
.include "config.inc"
.include "constants.inc"

# --- User A Execution-Entry ---
    user_a_code: 
        # 1. Invoke IPC SEND system call to transmit data
        li a0, IPC_CHANNEL_ID       # Argument 0: channel-ID for IPC tracking
        la a1, msg                  # Argument 1: Base address of the message buffer
        
        # Load the dynamically calculated message length
        la a2, msg_len_val          
        lw a2, 0(a2)                # Argument 2: Length of message in bytes (automatically calculated)
        
        li a7, SYS_CALL_SEND        # System Call ID: SEND
        ecall                       # Trap into M-Mode (OS kernel)
        
        # 2. Invoke EXIT system call to terminate process execution
        li a7, SYS_CALL_EXIT        # System Call ID: EXIT
        ecall                       # Trap into M-Mode (OS kernel)
        
        # 3. Fallback catch mechanism (Should never be reached)
        jal x0, USER_A_ERROR 

# --- User-A-Error-Fallback ---
    USER_A_ERROR:
        jal x0, USER_A_ERROR

# --- User A Data-Segment ---
.section .data
    msg:
        GET_USER_A_MSG              # Macro expansion: Inserts the literal string bytes
    msg_end:

    .align 2
    msg_len_val:
        .word (msg_end - msg)       # Assembler calculates the exact length at compile-time
