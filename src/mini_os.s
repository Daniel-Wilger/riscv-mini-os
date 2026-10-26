.option norvc           # Disable 16-bit compressed instructions to ensure strict 32-bit (4-byte) alignment for MEPC arithmetic
.section .text          
.globl _start           

.extern user_a_code
.extern user_b_code

.include "macros.inc"
.include "config.inc"
.include "constants.inc"

_start:
# --- Physical-Memory-Protection (PMP) ---
    # pmpaddr0: Holds the base address boundary for memory protection region 0
    # pmpcfg0:  Holds the configuration bits (R/W/X permissions and address matching mode)
    li t0, -1               # Set all bits to 1 (0xffffffff)
    srli t0, t0, 2          # Shift right by 2 to create the NAPOT top-of-range mask (0x3fffffff)
    csrw pmpaddr0, t0       # Grant access to the entire physical address space
    li t0, 0x1f             # Config byte 0x1f: Read=1, Write=1, Execute=1, Mode=NAPOT (11000)
    csrw pmpcfg0, t0
# --- Trap-Setup (mtvec) ---
    # mtvec: Machine Trap-Vector Base-Address Register. Holds the entry point for all traps/interrupts.
    la t0, trap_handler     # Load the absolute address of the central trap handler
    csrw mtvec, t0          # Register the handler address in mtvec
# --- Machine-Stack ---
    la sp, _machine_stack_top
# --- IPC-Initialization ---
    # Initialize the shared IPC memory state tracking variables before process launch
    
    # 1. Set free buffer capacity to SHARED_BUFFER_LEN
    li t0, SHARED_BUFFER_LEN            
    la t1, shared_buffer_free_bytes    
    sw t0, 0(t1)                        

    # 2. Set global IPC status to free/idle
    li t0, IPC_STATUS_FREE              
    la t1, ipc_status                   
    sw t0, 0(t1)

    # 3. Clear active IPC channel PIDs (set to IPC_FREE_PID)
    li t0, IPC_FREE_PID                 
    la t1, ipc_sender_pid               
    sw t0, 0(t1)
    la t1, ipc_receiver_pid             
    sw t0, 0(t1)
# --- Process-Variables-Initialization ---
    # Initialize the core scheduling state variables in memory
    
    # 1. Set the total system process count
    li t0, INITIAL_PROCESS_COUNT         
    la t1, num_process                  
    sw t0, 0(t1)

    # 2. Set the initial active process ID to START_PROCESS_ID (0)
    li t0, START_PROCESS_ID             
    la t1, current_process_pid              
    sw t0, 0(t1)
# --- Process-Initialization-Loop ---
    # Loop through all configured processes to set their initial states and prepare trap frames
    li t0, START_PROCESS_ID         # t0 = current loop PID (starts at 0)
    li t1, INITIAL_PROCESS_COUNT    # t1 = loop boundary
    li t2, STATE_READY              # t2 = target process state
    la t3, process_states           # t3 = base address of states array

    init_process_loop:
        beq t0, t1, start_first_user    # If all processes are initialized, break loop
        
        # Macro expansion: Expects current PID in t0. Mutates t4, t5 and t6.
        INIT_PROCESS_TRAPFRAME          
        
        sw t2, 0(t3)                    # Set current process state to STATE_READY
        addi t3, t3, 4                  # Advance to next state entry (4 bytes per word)
        addi t0, t0, 1                  # Increment current loop PID
        j init_process_loop
                
# --- Start-First-User ---
    start_first_user:
        # Macro expansion: Restores entire user context into hardware registers
        RESTORE_CONTEXT         
        mret                        # Formally switch to User Mode and jump to process PC

# ------------------------------------------------------------------------------
# TRAP-HANDLER
# ------------------------------------------------------------------------------
trap_handler:           
    # Macro expansion: Secure full user context before modifying registers
    SAVE_CONTEXT
    
    # Load the dedicated kernel stack pointer
    la sp, _machine_stack_top       
    
    # Determine the cause of the trap
    csrr t0, mcause                 # t0 = mcause
    li t1, MCAUSE_ECALL_U_MODE
    beq t0, t1, syscall_handler     # If ecall, route to system call handler
    
    # Fallback for unexpected interrupts/exceptions
    jal x0, default_trap_handler


# ------------------------------------------------------------------------------
# ECALL-HANDLER (SYSCALL-HANDLER)
# ------------------------------------------------------------------------------
syscall_handler:
    # Route to the specific system call implementation based on a7
    # Note: mepc arithmetic is handled inside each individual syscall!
    li t0, SYS_CALL_EXIT            # Load configuration-defined EXIT ID
    beq a7, t0, sys_exit            # If a7 == SYS_CALL_EXIT, route to sys_exit
    
    li t0, SYS_CALL_RECEIVE         # Load configuration-defined RECEIVE ID
    beq a7, t0, sys_receive         # If a7 == SYS_CALL_RECEIVE, route to sys_receive
    
    li t0, SYS_CALL_SEND            # Load configuration-defined SEND ID
    beq a7, t0, sys_send            # If a7 == SYS_CALL_SEND, route to sys_send
    
    # Fallback for unhandled/unknown system calls
    j default_syscall_handler

### ------------------------ SCHEDULER ------------------------
scheduler:
    la t6, current_process_pid   # Address of current_process_pid
    lw t0, 0(t6)                 # t0 = PID of the currently running process

    # Setup for finde_next_ready-loop
    la t5, num_process       
    lw t5, 0(t5)                 # t5 = Total number of processes (constant)
    la t2, process_states        # t2 = Base address of the states array
    li t4, STATE_READY           # t4 = Target state to compare against

    find_next_ready:
        # 1. Advance to next process index with wrap-around
        addi t0, t0, 1           
        rem t0, t0, t5               # t0 = Next target PID to evaluate

        # 2. Calculate address of this process's state (4 bytes per word)
        slli t1, t0, 2              
        add t1, t2, t1               # t1 = Precise pointer to process_states[t0]
        lw t3, 0(t1)                 # t3 = Fetch state (READY/WAITING/...)

        # 3. If the process is not READY, keep searching
        bne t3, t4, find_next_ready 

    # 4. READY process found, update the kernel's active PID tracking
    sw t0, 0(t6)             

    # 5. Handover control back to the selected process
    RESTORE_CONTEXT       
    mret                         # Switch back to User Mode

# ==============================================================================
# SYS_EXIT (Syscall ID: 10)
# DESCRIPTION: Permanently terminates the currently executing process.
# ==============================================================================
sys_exit:
    # 1. Load the active process ID (Who am I?)
    la t0, current_process_pid      
    lw t1, 0(t0)                    # t1 = current PID

    # 2. Update the process state to STATE_TERMINATED
    la t2, process_states           # Base address of the process state array
    slli t3, t1, 2                  # PID * 4 (Byte-offset for 32-bit words)
    add t2, t2, t3                  # t2 = Pointer to current process state slot
    li t4, STATE_TERMINATED         # Load architecture state constant
    sw t4, 0(t2)                    # Mark process as permanently terminated in RAM

    # TODO:3. Handle MEPC tracking for security
    # NOTE: We deliberately do NOT advance mepc here. If a scheduler bug 
    # accidentally re-activates this terminated process, it will safely 
    # freeze on the exit 'ecall' instruction rather than corrupting memory.

    # 4. Jump to scheduler to select the next ready process
    j scheduler

# ==============================================================================
# SYS_RECEIVE (Syscall ID: 63)
# DESCRIPTION: Handles IPC data retrieval from the shared kernel buffer.
#
# INPUTS (Registers passed from User Mode):
#   a0: channel-ID (Must match IPC_CHANNEL_ID)
#   a1: Base address of the destination user buffer where data will be stored
#   a2: Maximum length/capacity of the destination user buffer in bytes
#   a7: Syscall ID (SYS_CALL_RECEIVE / 63)
#
# OUTPUTS (Returned via Trap Frame into User Mode):
#   a0: Return Code (IPC_RETURN_SUCCESS or Error Code)
#   a2: Updated remaining space in the user buffer (0 if fully filled)
# ==============================================================================
sys_receive:
    # 1. Validate channel-ID
    li t0, IPC_CHANNEL_ID
    bne a0, t0, default_receive_channel_id

    # 2. Track receiver PID
    la t0, ipc_receiver_pid 
    lw t0, 0(t0)                    # t0 = ipc_receiver_pid
    
    # If this process is already the registered receiver, check IPC status
    la t1, current_process_pid
    lw t1, 0(t1)
    beq t0, t1, receive_check_ipc_status  
    
    # If no receiver is registered yet, claim the channel
    li t1, IPC_FREE_PID 
    beq t0, t1, initial_receive
    
    # Access Denied: Foreign process tries to intercept the IPC channel
    GET_TRAP_FRAME_ADDRESS t0, t1   # Calculates address in t0, uses t1 as helper
    li t1, IPC_RETURN_ACCESS_DENIED 
    sw t1, REGOFF_X10(t0)           # Set return value a0 = IPC_RETURN_ACCESS_DENIED
    
    # Advance MEPC to the next instruction so the user process resumes 
    # and can process the returned error code.
    lw t2, REGOFF_MEPC(t0)
    addi t2, t2, 4
    sw t2, REGOFF_MEPC(t0)          # mepc = mepc + 4 (skip the ecall instruction)

    # Keep the process active by setting its state to READY. 
    # Since this is an immediate return, the process does not need to block.
    li t2, STATE_READY
    sw t2, PROCESS_STATE(t0)        # Transition current process state to READY
    j scheduler


    initial_receive:        
        # Register the current process as the official IPC receiver
        la t0, current_process_pid
        lw t0, 0(t0)                
        la t2, ipc_receiver_pid      
        sw t0, 0(t2)                # ipc_receiver_pid = current_process_pid
        
        # Check if data is already available to read
        la t0, ipc_status
        lw t0, 0(t0)
        li t1, IPC_STATUS_ACTIVE
        beq t0, t1, receive_init_loop
        
        # Note: If SENDING_SUCCESS, the sender already fits completely into the shared
        # buffer. We bypass the upfront length validation because the sender's remaining 
        # length register (a2) has already reached 0, making a comparison impossible.
        li t1, IPC_STATUS_SENDING_SUCCESS       
        beq t0, t1, receive_init_loop

        # Channel is empty/free -> Put receiver to sleep and invoke scheduler
        GET_TRAP_FRAME_ADDRESS t0, t1   # Calculates address in t0, uses t1 as helper
        li t1, STATE_WAITING
        sw t1, PROCESS_STATE(t0)
        
        # Decrement mepc by 4 so the process retries the ecall upon waking up
        lw t1, REGOFF_MEPC(t0)
        addi t1, t1, -4
        sw t1, REGOFF_MEPC(t0)
        j scheduler


    receive_check_ipc_status:
        la t0, ipc_status
        lw t0, 0(t0)                # t0 = ipc_status

        # If IPC transmission is active or data needs draining, jump to loop init        
        li t1, IPC_STATUS_ACTIVE
        beq t0, t1, receive_init_loop
        li t1, IPC_STATUS_SENDING_SUCCESS
        beq t0, t1, receive_init_loop     
        
        # Safety fallback
        j default_receive_check_ipc_status
    

    receive_init_loop:
        GET_TRAP_FRAME_ADDRESS t0, t1   # Calculates address in t0, uses t1 as helper
        # Load user arguments from Trap Frame
        lw t1, REGOFF_X11(t0)           # t1 = user a1 (buffer address)
        lw t2, REGOFF_X12(t0)           # t2 = user a2 (buffer remaining length)
        la t3, shared_buffer            # t3 = shared buffer base address
        la t4, shared_buffer_free_bytes
        lw t4, 0(t4)                    # t4 = active free bytes count

    receive_loop:
        beq t2, x0, receive_buffer_too_small    # Error if user buffer runs out of space
        li t6, SHARED_BUFFER_LEN
        beq t4, t6, receive_done                # Success if shared buffer is fully drained
        lb t5, 0(t3)                            # Load byte from shared buffer
        sb t5, 0(t1)                            # Store byte into user buffer
        addi t1, t1, 1                          # Advance user buffer pointer
        addi t2, t2, -1                         # Decrement user remaining length
        addi t3, t3, 1                          # Advance shared buffer pointer
        addi t4, t4, 1                          # Increment available free bytes
        j receive_loop  

    receive_done:
        # Checkpoint the current progress of the IPC transaction (buffer pointers 
        # and remaining lengths) into the Trap Frame, and sync global kernel RAM.
        RECEIVE_STORE t1, t2, t4
        
        # Evaluate if transmission is entirely completed
        la t0, ipc_status
        lw t1, 0(t0)                            # t1 = ipc_status
        li t2, IPC_STATUS_SENDING_SUCCESS
        beq t1, t2, receive_totaly_done
        # mepc still points on the ecall instruction
        # Process stays in WAITING state and will re-evaluate the ecall.
        GET_TRAP_FRAME_ADDRESS t0, t1           # Calculates address in t0, uses t1 as helper
        li t4, STATE_WAITING
        sw t4, PROCESS_STATE(t0)
        
        SET_SENDER_STATE_READY
        j scheduler 

    receive_totaly_done:    
        # Terminate transaction successfully
        li t2, IPC_STATUS_SUCCESS
        sw t2, 0(t0)

        # Set user return value a0 = IPC_RETURN_SUCCESS
        GET_TRAP_FRAME_ADDRESS t0, t1   # Calculates address in t0, uses t1 as helper
        li t1, IPC_RETURN_SUCCESS
        sw t1, REGOFF_X10(t0)
        
        # Put receiver to WAITING state until transaction wraps up
        li t4, STATE_WAITING
        sw t4, PROCESS_STATE(t0)
        
        # Advance mepc by 4 to move receiver to the next instruction
        lw t4, REGOFF_MEPC(t0)      
        addi t4, t4, 4             
        sw t4, REGOFF_MEPC(t0)  
        
        SET_SENDER_STATE_READY
        j scheduler

    receive_buffer_too_small:
        # Checkpoint the current progress of the IPC transaction (buffer pointers 
        # and remaining lengths) into the Trap Frame, and sync global kernel RAM.
        RECEIVE_STORE t1, t2, t4
        
        # Set transaction status to buffer overflow error
        la t0, ipc_status
        li t1, IPC_STATUS_ERROR_BUFFER_OVERFLOW
        sw t1, 0(t0)
        
        # Set user return value a0 = IPC_RETURN_ERROR_BUFFER_OVERFLOW
        GET_TRAP_FRAME_ADDRESS t0, t1   # Calculates address in t0, uses t1 as helper
        li t1, IPC_RETURN_ERROR_BUFFER_OVERFLOW
        sw t1, REGOFF_X10(t0)
        
        # Advance mepc by 4 to proceed user process despite the error
        lw t4, REGOFF_MEPC(t0)      
        addi t4, t4, 4             
        sw t4, REGOFF_MEPC(t0) 
        
        SET_SENDER_STATE_READY
        j scheduler
        
# ==============================================================================
# SYS_SEND (Syscall ID: 64)
# DESCRIPTION: Handles IPC data transmission by copying user bytes into the 
#              shared kernel buffer. Blocks when the buffer is full.
#
# INPUTS (Registers passed from User Mode):
#   a0: channel-ID (Must match IPC_CHANNEL_ID)
#   a1: Base address of the source message string/buffer in user space
#   a2: Total length of the message to be transmitted in bytes
#   a7: Syscall ID (SYS_CALL_SEND / 64)
#
# OUTPUTS (Returned via Trap Frame into User Mode):
#   a0: Return Code (IPC_RETURN_SUCCESS or Error Code)
# ==============================================================================
sys_send:
    # 1. Validate channel-ID
    li t0, IPC_CHANNEL_ID                 
    bne a0, t0, default_send_channel_id       # If a0 != IPC_CHANNEL_ID, redirect to default handler

    # 2. Track sender PID
    la t0, ipc_sender_pid   
    lw t0, 0(t0)                      # t0 = ipc_sender_pid

    # If this process is already the registered sender, verify the channel status
    la t1, current_process_pid
    lw t1, 0(t1)
    beq t0, t1, send_check_ipc_status

    # If the channel is currently unclaimed, proceed to register ownership
    li t1, IPC_FREE_PID
    beq t0, t1, initial_send

    # Access Denied: Foreign process attempts to hijack or disrupt the channel
    GET_TRAP_FRAME_ADDRESS t0, t1   # Calculates address in t0, uses t1 as helper
    li t1, IPC_RETURN_ACCESS_DENIED 
    sw t1, REGOFF_X10(t0)           # Set return value a0 = IPC_RETURN_ACCESS_DENIED

    # Advance MEPC to the next instruction so the user process resumes 
    # and can process the returned error code.
    lw t2, REGOFF_MEPC(t0)
    addi t2, t2, 4
    sw t2, REGOFF_MEPC(t0)          # mepc = mepc + 4 (skip the ecall instruction)

    # Keep the process active by setting its state to READY. 
    # Since this is an immediate return, the process does not need to block.
    li t2, STATE_READY
    sw t2, PROCESS_STATE(t0)        # Transition current process state to READY
    j scheduler


    initial_send:
        # Register the current process as the official IPC sender
        la t0, current_process_pid
        lw t0, 0(t0)           
        la t2, ipc_sender_pid      
        sw t0, 0(t2)                    # ipc_sender_pid = current_process_pid

        # Mark the IPC channel status as active to signal the receiver
        la t0, ipc_status
        li t1, IPC_STATUS_ACTIVE
        sw t1, 0(t0)                    # ipc_status = IPC_STATUS_ACTIVE
        j send_init_loop 


    send_check_ipc_status: 
        la t0, ipc_status
        lw t0, 0(t0)                    # t0 = ipc_status

        # If transmission is active, jump straight to loading the context
        li t1, IPC_STATUS_ACTIVE
        beq t0, t1, send_init_loop

        # If transaction finished successfully, jump to the cleanup routine
        li t1, IPC_STATUS_SUCCESS
        beq t0, t1, ipc_success_routine 

        # If the receiver flagged a buffer overflow, jump to the error routine
        li t1, IPC_STATUS_ERROR_BUFFER_OVERFLOW
        beq t0, t1, ipc_buffer_overflow_routine

        # Safety fallback for unexpected status values
        j default_send_check_ipc_status


    send_init_loop:
        GET_TRAP_FRAME_ADDRESS t0, t1   # Calculates address in t0, uses t1 as helper
        # Restore user arguments and internal state counters
        lw t1, REGOFF_X11(t0)           # t1 = a1 (message user address)
        lw t2, REGOFF_X12(t0)           # t2 = a2 (remaining message length)
        la t3, shared_buffer            # t3 = shared buffer base address
        la t4, shared_buffer_free_bytes
        lw t4, 0(t4)                    # t4 = currently available free bytes
        
        # Boundary checks before entering the copy cycle
        beq t2, x0, send_totaly_done    # If message is completely sent, wrap up
        beq t4, x0, send_done           # If shared buffer is full, block sender


    send_loop:
        lb t5, 0(t1)                    # Load byte from user message space
        sb t5, 0(t3)                    # Store byte into shared kernel buffer
        addi t1, t1, 1                  # Advance user message pointer
        addi t2, t2, -1                 # Decrement remaining message bytes
        addi t3, t3, 1                  # Advance shared buffer pointer
        addi t4, t4, -1                 # Decrement available free bytes count
        
        # Dynamic checks within the transmission loop
        beq t2, x0, send_totaly_done    # Success transition if message is fully processed
        beq t4, x0, send_done           # Block transition if shared buffer runs out of space
        j send_loop  

    send_done:
        # Checkpoint the current progress of the IPC transaction (buffer pointers 
        # and remaining lengths) into the Trap Frame, and sync global kernel RAM.
        SEND_STORE t1, t2, t4   
            
        # Put sender into WAITING state since the shared buffer is full
        GET_TRAP_FRAME_ADDRESS t0, t1   
        li t4, STATE_WAITING
        sw t4, PROCESS_STATE(t0)
        
        # Wake up the receiver to start draining the buffer
        SET_RECEIVER_STATE_READY        
        j scheduler 


    send_totaly_done:
        # Commit the remaining free bytes back to global RAM
        la t0, shared_buffer_free_bytes
        sw t4, 0(t0)
        
        # Advance state to let the receiver know the full content is available
        la t0, ipc_status
        li t1, IPC_STATUS_SENDING_SUCCESS
        sw t1, 0(t0)
        
        # Wake up the receiver for the final processing pass
        SET_RECEIVER_STATE_READY
        
        # Put sender into WAITING state until the receiver completely drains the channel
        GET_TRAP_FRAME_ADDRESS t0, t1   
        addi t1, x0, STATE_WAITING
        sw t1, PROCESS_STATE(t0)
        j scheduler



    ipc_success_routine:       
        # Set user return value to indicate a fully successful transaction
        GET_TRAP_FRAME_ADDRESS t0, t1   
        li t1, IPC_RETURN_SUCCESS
        sw t1, REGOFF_X10(t0)           # return a0 = IPC_RETURN_SUCCESS
        j ipc_master_reset


    ipc_buffer_overflow_routine:
        # Set user return value to indicate a receiver-side overflow error
        GET_TRAP_FRAME_ADDRESS t0, t1   
        li t1, IPC_RETURN_ERROR_BUFFER_OVERFLOW
        sw t1, REGOFF_X10(t0)           # return a0 = IPC_RETURN_ERROR_BUFFER_OVERFLOW
        j ipc_master_reset


    ipc_master_reset: 
        # Tear down the channel: clear status and release ownership tokens
        la t0, ipc_status 
        li t1, IPC_STATUS_FREE
        sw t1, 0(t0)
        
        SET_RECEIVER_STATE_READY

        # Reset ipc_sender_pid & ipc_receiver_pid
        li t0, IPC_FREE_PID
        la t1, ipc_sender_pid
        sw t0, 0(t1)
        la t1, ipc_receiver_pid
        sw t0, 0(t1)

        # Advance mepc by 4 to move receiver to the next instruction
        GET_TRAP_FRAME_ADDRESS t0, t1
        lw t4, REGOFF_MEPC(t0)      
        addi t4, t4, 4             
        sw t4, REGOFF_MEPC(t0)  
            
        j scheduler


## ---------------- DEFAULT_HANDLER ------------------------
# ==============================================================================
# DEFAULT HANDLERS (Debugging Dead-Ends / Traps Stubs)
# ==============================================================================
    # 1. Unhandled Trap (mcause != 8) -> e.g., Illegal Instruction, Access Fault
    default_trap_handler: 
        j default_trap_handler     

    # 2. Unknown Syscall (mcause == 8, but a7 doesn't contain a valid Syscall-ID)
    default_syscall_handler: 
        j default_syscall_handler   

    # 3. IPC Error: Invalid channel-id during RECEIVE
    default_receive_channel_id: 
        j default_receive_channel_id    

    # 4. IPC Error: Invalid channel-id during SEND
    default_send_channel_id:
        j default_send_channel_id   

    # 5. IPC Error: Unexpected status fallback during send_check_ipc_status
    default_send_check_ipc_status:
        j default_send_check_ipc_status  
    
    #6. IPC Error: Unexpected status fallback during receive_check_ipc_status
    default_receive_check_ipc_status:
        j default_receive_check_ipc_status     

### ============================================================================
### INITIALIZED DATA SEGMENT (.data)
### ============================================================================
# TODO: configs / constants?
.section .data
    .align 2                        
    
    # Table containing the initial top-of-stack addresses for user processes 
    user_stack_tops:
        .word _user_a_stack_top    
        .word _user_b_stack_top    
    
    # Table containing the entry point program counter (PC) addresses for user processes
    process_pc:
        .word user_a_code
        .word user_b_code

### ============================================================================
### UNINITIALIZED DATA (.bss)
### ============================================================================      
.section .bss
    .global shared_buffer
    .global process_states
    .global shared_buffer_free_bytes
    .global ipc_status
    .global ipc_sender_pid
    .global ipc_receiver_pid
    .global num_process
    .global current_process_pid
    .global process_trap_frames

    
    # 1. IPC shared message buffer (occupies SHARED_BUFFER_LEN (config.inc) bytes)
    shared_buffer:
        .fill SHARED_BUFFER_LEN, 1, 0
    # Re-align to 4-byte boundary (word alignment) as SHARED_BUFFER_LEN can be any arbitrary natural number
    .align 2

    process_states:
        .fill INITIAL_PROCESS_COUNT, 4, 0

    # 2. Kernel status an management variables
    shared_buffer_free_bytes:   .space 4
    ipc_status:                 .space 4
    ipc_sender_pid:             .space 4
    ipc_receiver_pid:           .space 4
    num_process:                .space 4
    current_process_pid:        .space 4

    # 3. Storage block for process trap frames
    process_trap_frames:
        .space INITIAL_PROCESS_COUNT * TRAP_FRAME_SIZE
    .align 2
