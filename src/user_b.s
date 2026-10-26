.section .text
.globl user_b_code
.include "macros.inc"
.include "config.inc"
.include "constants.inc"

# --- User B Execution-Entry ---
    user_b_code: 
        # 1. Initialize user buffer remaining length
        la t0, buffer_remaining_length
        li t1, USER_BUFFER_LENGTH
        sw t1, 0(t0)
        
        # 2. Invoke IPC RECEIVE system call to retrieve data
        li a0, IPC_CHANNEL_ID           # Argument 0: Channel-ID for IPC tracking
        la a1, buffer                   # Argument 1: Base address of the destination buffer
        
        la t0, buffer_remaining_length
        lw a2, 0(t0)                    # Argument 2: Maximum length of user buffer in bytes
        
        li a7, SYS_CALL_RECEIVE         # System Call ID: RECEIVE
        ecall                           # Trap into M-Mode (OS kernel)
        
        # Save the updated remaining buffer length back to memory
        sw a2, 0(t0)                    
        
        # 3. Invoke EXIT system call to terminate process execution
        li a7, SYS_CALL_EXIT            # System Call ID: EXIT
        ecall                           # Trap into M-Mode (OS kernel)
        
        # 4. Fallback catch mechanism (Should never be reached)
        jal x0, USER_B_ERROR 

# --- User-B-Error-Fallback ---
    USER_B_ERROR:
        jal x0, USER_B_ERROR            # Tight infinite loop to freeze execution safely

# --- User B-Data-Segment / BSS ---
.section .bss
    buffer:
        .space USER_BUFFER_LENGTH       # Space for the incoming message buffer (uses config constant)
        
    buffer_remaining_length: 
        .space 4                        # Stores the remaining capacity/length of the buffer
