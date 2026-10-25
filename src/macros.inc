# ==============================================================================
# SYSTEM-MAKROS (macros.inc)
# ==============================================================================
# ==============================================================================
# MACRO: INIT_PROCESS_TRAPFRAME
# DESCRIPTION: Prepares the initial hardware context within a process's trap frame.
# INTERFACE:   Input:  t0 = Target Process ID (PID)
#              Outputs: None (Modifies memory in process_trap_frames)
#              Scratch: Mutates t4, t5, t6
# ==============================================================================
.macro INIT_PROCESS_TRAPFRAME
    # 1. Calculate the base address of the specific trap frame
    slli t5, t0, TRAP_FRAME_SHIFT   # Offset = PID * 256 bytes
    la t4, process_trap_frames      # Base address of all trap frames
    add t5, t4, t5                  # t5 = Target trap frame address

    # 2. Fetch and store the entry point (Program Counter) into MEPC slot
    slli t4, t0, 2                  # t4 = Word offset (PID * 4)
    la t6, process_pc               # Base address of process_pc array
    add t6, t4, t6                  # t6 = Address of specific process_pc entry
    lw t6, 0(t6)                    # t6 = Initial Program Counter (PC) value
    sw t6, REGOFF_MEPC(t5)          # Store into trap frame MEPC slot

    # 3. Fetch and store the User Stack Pointer into X2 (sp) slot
    la t6, user_stack_tops          # Base address of user_stack_tops array
    add t6, t4, t6                  # t6 = Address of specific stack top entry
    lw t6, 0(t6)                    # t6 = Initial User Stack Pointer (sp) value
    sw t6, REGOFF_X2(t5)            # Store into trap frame X2 (sp) slot

    # 4. Initialize MSTATUS slot to User Mode (0x0000)
    li t6, 0x0000                   
    sw t6, REGOFF_MSTATUS(t5)       # Set MPP = 00 (User Mode) in trap frame
.endm

# ==============================================================================
# MACRO: RESTORE_CONTEXT
# DESCRIPTION: Loads a process's saved hardware context from its Trap Frame 
#              back into the CPU registers right before returning to User Mode.
# INTERFACE:   Input:  None (Implicitly reads current_process_pid)
#              Outputs: Destroys all kernel registers, fully restoring User state.
#              Scratch: Temporarily uses t0 and t1 as base/offset pointers.
# ==============================================================================
.macro RESTORE_CONTEXT
    # 1. Calculate the base address of the CURRENT process's trap frame
    la t0, current_process_pid
    lw t0, 0(t0)                    # t0 = current PID
    la t1, process_trap_frames
    slli t0, t0, TRAP_FRAME_SHIFT
    add t0, t1, t0                  # t0 = Base address of target Trap Frame
    
    # 2. Restore Control and Status Registers (CSRs)
    lw t1, REGOFF_MEPC(t0)
    csrw mepc, t1                   # Setup return target PC for mret
    
    lw t1, REGOFF_MSTATUS(t0)
    csrw mstatus, t1                # Setup target privilege mode (User)
    
    # 3. Save the active kernel stack pointer into mscratch for the next trap
    csrw mscratch, sp

    # 4. Restore general purpose registers (Skipping x5/t0 for now)
    lw x1,  REGOFF_X1(t0)           # ra
    lw x2,  REGOFF_X2(t0)           # sp (User Stack Pointer)
    lw x3,  REGOFF_X3(t0)           # gp
    lw x4,  REGOFF_X4(t0)           # tp
    # x5 (t0) is skipped because it currently holds our Trap Frame base address!
    lw x6,  REGOFF_X6(t0)           # t1
    lw x7,  REGOFF_X7(t0)           # t2
    lw x8,  REGOFF_X8(t0)           # s0/fp
    lw x9,  REGOFF_X9(t0)           # s1
    lw x10, REGOFF_X10(t0)          # a0
    lw x11, REGOFF_X11(t0)          # a1
    lw x12, REGOFF_X12(t0)          # a2
    lw x13, REGOFF_X13(t0)          # a3
    lw x14, REGOFF_X14(t0)          # a4
    lw x15, REGOFF_X15(t0)          # a5
    lw x16, REGOFF_X16(t0)          # a6
    lw x17, REGOFF_X17(t0)          # a7
    lw x18, REGOFF_X18(t0)          # s2
    lw x19, REGOFF_X19(t0)          # s3
    lw x20, REGOFF_X20(t0)          # s4
    lw x21, REGOFF_X21(t0)          # s5
    lw x22, REGOFF_X22(t0)          # s6
    lw x23, REGOFF_X23(t0)          # s7
    lw x24, REGOFF_X24(t0)          # s8
    lw x25, REGOFF_X25(t0)          # s9
    lw x26, REGOFF_X26(t0)          # s10
    lw x27, REGOFF_X27(t0)          # s11
    lw x28, REGOFF_X28(t0)          # t3
    lw x29, REGOFF_X29(t0)          # t4
    lw x30, REGOFF_X30(t0)          # t5
    lw x31, REGOFF_X31(t0)          # t6

    # 5. The "Final Shot": Restore t0 (x5) itself
    # Since t0 is no longer needed as a base pointer, load its original User value
    lw t0, REGOFF_X5(t0)
.endm


# ==============================================================================
# MACRO: SAVE_CONTEXT
# DESCRIPTION: Atomically saves all user registers and CSRs into the active 
#              process's trap frame upon entering an exception/interrupt.
# INTERFACE:   Input:  None (Implicitly reads current_process_pid)
#              Outputs: Saves state to memory. Establishes kernel stack context.
#              Scratch: Uses t0, t1, t2 internally after backing them up.
# ==============================================================================
#TODO: GET_TRAP_FRAME_ADDRES benutzen
.macro SAVE_CONTEXT
    # 1. Swap User SP with Kernel SP stored in mscratch
    csrrw sp, mscratch, sp       
    
    # 2. Temporarily back up t0 and t1 on the machine stack to free them up
    addi sp, sp, -8
    sw t0, 0(sp)
    sw t1, 4(sp)
    
    # 3. Calculate the base address of the current process's trap frame
    la t0, current_process_pid
    lw t0, 0(t0)                    # t0 = current PID
    la t1, process_trap_frames
    slli t0, t0, TRAP_FRAME_SHIFT
    add t0, t1, t0                  # t0 = Target Trap Frame base address

    # 4. Save general purpose registers (Skipping x2, x5, x6 temporarily)
    sw x1,  REGOFF_X1(t0)           # ra
    sw x3,  REGOFF_X3(t0)           # gp
    sw x4,  REGOFF_X4(t0)           # tp
    sw x7,  REGOFF_X7(t0)           # t2
    sw x8,  REGOFF_X8(t0)           # s0/fp
    sw x9,  REGOFF_X9(t0)           # s1
    sw x10, REGOFF_X10(t0)          # a0
    sw x11, REGOFF_X11(t0)          # a1
    sw x12, REGOFF_X12(t0)          # a2
    sw x13, REGOFF_X13(t0)          # a3
    sw x14, REGOFF_X14(t0)          # a4
    sw x15, REGOFF_X15(t0)          # a5
    sw x16, REGOFF_X16(t0)          # a6
    sw x17, REGOFF_X17(t0)          # a7
    sw x18, REGOFF_X18(t0)          # s2
    sw x19, REGOFF_X19(t0)          # s3
    sw x20, REGOFF_X20(t0)          # s4
    sw x21, REGOFF_X21(t0)          # s5
    sw x22, REGOFF_X22(t0)          # s6
    sw x23, REGOFF_X23(t0)          # s7
    sw x24, REGOFF_X24(t0)          # s8
    sw x25, REGOFF_X25(t0)          # s9
    sw x26, REGOFF_X26(t0)          # s10
    sw x27, REGOFF_X27(t0)          # s11
    sw x28, REGOFF_X28(t0)          # t3
    sw x29, REGOFF_X29(t0)          # t4
    sw x30, REGOFF_X30(t0)          # t5
    sw x31, REGOFF_X31(t0)          # t6
    
    # 5. Move Trap Frame pointer to t2 to recover user t0 & t1 from stack
    addi t2, t0, 0                  # t2 = Trap Frame base address
    lw t0, 0(sp)                    # Restore original User t0 from machine stack
    lw t1, 4(sp)                    # Restore original User t1 from machine stack
    addi sp, sp, 8                  # Reclaim stack space
    
    sw x5,  REGOFF_X5(t2)           # Store User t0 into Trap Frame
    sw x6,  REGOFF_X6(t2)           # Store User t1 into Trap Frame
    
    # 6. Retrieve original User SP from mscratch and save it
    csrr t0, mscratch               # t0 = User SP
    sw t0, REGOFF_X2(t2)            # Store User SP into Trap Frame

    # 7. Save Control and Status Registers (CSRs)
    csrr t1, mepc
    sw t1, REGOFF_MEPC(t2)          # Save address of the ecall instruction
    csrr t1, mstatus
    sw t1, REGOFF_MSTATUS(t2)       # Save privilege mode state
.endm


# ==============================================================================
# MACRO: GET_TRAP_FRAME_ADDRESS
# DESCRIPTION: Calculates the base address of the currently active process's 
#              trap frame and stores it in the destination register.
# INTERFACE:   Input:  rd      = Destination register to hold the calculated address
#                      scratch = Temporary register used for intermediate math
# ==============================================================================
.macro GET_TRAP_FRAME_ADDRESS rd, scratch
    la \rd, current_process_pid
    lw \rd, 0(\rd)                  # \rd = current PID
    la \scratch, process_trap_frames 
    slli \rd, \rd, TRAP_FRAME_SHIFT   
    add \rd, \rd, \scratch          # \rd = calculated trap frame address
.endm


# ==============================================================================
# MACRO: RECEIVE_STORE
# DESCRIPTION: Saves the current user buffer address, remaining length, and 
#              updated shared buffer free byte count back into the architecture.
# INPUTS:      reg_buf_addr = Register containing current user buffer pointer (t1)
#              reg_rem_len  = Register containing remaining length to read (t2)
#              reg_free_bytes = Register containing current free bytes count (t4)
# ==============================================================================
.macro RECEIVE_STORE reg_buf_addr, reg_rem_len, reg_free_bytes
    # We use a non-destructive path by storing directly into the Trap Frame
    # Access Trap Frame using t0 as base and t5 as scratch to preserve loop registers
    GET_TRAP_FRAME_ADDRESS t0, t5
    
    sw \reg_buf_addr, REGOFF_X11(t0)   # Update user saved a1 (buffer pointer)
    sw \reg_rem_len,  REGOFF_X12(t0)   # Update user saved a2 (remaining length)
    
    la t5, shared_buffer_free_bytes
    sw \reg_free_bytes, 0(t5)          # Sync the kernel's free byte counter
.endm  


# ==============================================================================
# MACRO: SEND_STORE
# DESCRIPTION: Saves the current user message address, remaining length, and 
#              updated shared buffer free byte count back into the architecture.
# INPUTS:      reg_buf_addr   = Register containing current user message pointer (t1)
#              reg_rem_len    = Register containing remaining length to write (t2)
#              reg_free_bytes = Register containing current free bytes count (t4)
# ==============================================================================
.macro SEND_STORE reg_buf_addr, reg_rem_len, reg_free_bytes
    # Access Trap Frame using t0 as base and t5 as scratch to preserve loop registers
    GET_TRAP_FRAME_ADDRESS t0, t5
    
    sw \reg_buf_addr, REGOFF_X11(t0)   # Update user saved a1 (message pointer)
    sw \reg_rem_len,  REGOFF_X12(t0)   # Update user saved a2 (remaining length)
    
    la t5, shared_buffer_free_bytes
    sw \reg_free_bytes, 0(t5)          # Sync the kernel's free byte counter
.endm


# ==============================================================================
# MACRO: SET_RECEIVER_STATE_READY
# DESCRIPTION: Locates the registered IPC receiver process and transitions 
#              its state to STATE_READY so the scheduler can resume it.
# SCRATCH:     Destroys t5, t6
# ==============================================================================
.macro SET_RECEIVER_STATE_READY
    la t6, ipc_receiver_pid
    lw t6, 0(t6)                        # t6 = PID of the registered receiver
    
    # If no valid receiver is currently registered (PID < 0), bypass state change
    blt t6, x0, no_receiver_found\@
    
    la t5, process_trap_frames      
    slli t6, t6, TRAP_FRAME_SHIFT   
    add t6, t6, t5                      # t6 = Base address of receiver's Trap Frame
    
    li t5, STATE_READY
    sw t5, PROCESS_STATE(t6)            # Wake up receiver: set state to READY

no_receiver_found\@:
.endm
      
   
# ==============================================================================
# MACRO: SET_SENDER_STATE_READY
# DESCRIPTION: Locates the registered IPC sender process and transitions 
#              its state to STATE_READY so the scheduler can resume it.
# SCRATCH:     Destroys t4, t5, t6
# ==============================================================================
.macro SET_SENDER_STATE_READY
    la t6, ipc_sender_pid
    lw t6, 0(t6)                        # t6 = PID of the registered sender
    
    # Safety check: If no valid sender is registered (PID < 0), bypass state change
    blt t6, x0, no_sender_found\@
    
    la t5, process_trap_frames      
    slli t6, t6, TRAP_FRAME_SHIFT   
    add t6, t6, t5                      # t6 = Base address of sender's Trap Frame
    
    li t4, STATE_READY
    sw t4, PROCESS_STATE(t6)            # Wake up sender: set state to READY

no_sender_found\@:
.endm
