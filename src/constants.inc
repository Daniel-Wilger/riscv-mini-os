# ==============================================================================
# INTERNAL ARCHITECTURE CONSTANTS (constants.inc)
# ==============================================================================
# WARNING: Changes here alter the kernel logic and will cause crashes!

# --- START SETUP ---
.equ START_PROCESS_ID,  0

# --- PROCESS STATES ---
.equ STATE_READY,       0   
#.equ STATE_RUNNING,     1   # Implicitly replaced by the current kernel state in cooperative/trap design
.equ STATE_WAITING,     2
.equ STATE_TERMINATED,  3

# --- IPC CHANNEL STATUS (Stored in RAM within ipc_status) ---
.equ IPC_STATUS_FREE,                   0   # Unclaimed / Free for new connections
.equ IPC_STATUS_ERROR_BUFFER_OVERFLOW,  -1   
.equ IPC_STATUS_ACTIVE,                 1   # Claimed / Transmission actively running
.equ IPC_STATUS_SENDING_SUCCESS,        2   # Claimed / Internal sync: Sender has yielded all data and is waiting.
                                            # Receiver is allowed to read remaining data.
.equ IPC_STATUS_SUCCESS,                3   # Claimed / Entire transaction successfully completed

# --- IPC FREE PIDs ---
.equ IPC_FREE_PID,     -1

# --- IPC channel-ID ---
.equ IPC_CHANNEL_ID,    0

# --- IPC RETURN VALUES (Passed to user processes via register a0) ---
.equ IPC_RETURN_SUCCESS,                0   # Entire IPC transaction successfully completed
.equ IPC_RETURN_ACCESS_DENIED,          -1   # Foreign process attempts to access IPC (channel claimed)
.equ IPC_RETURN_ERROR_BUFFER_OVERFLOW, -2   # Receiver buffer too small for the message

# --- Syscalls: a7 values ---
.equ SYS_CALL_EXIT,         10
.equ SYS_CALL_RECEIVE,      63
.equ SYS_CALL_SEND,         64

# --- Trap: MCAUSE values ---
.equ MCAUSE_ECALL_U_MODE,   8       # Exception code for ecall from User Mode

# --- TRAP FRAME OFFSETS (RV32 ABI) ---
    .equ REGOFF_X1,  4      # ra (Return Address)
    .equ REGOFF_X2,  8      # sp (User Stack Pointer)
    .equ REGOFF_X3,  12     # gp (Global Pointer)
    .equ REGOFF_X4,  16     # tp (Thread Pointer)
    .equ REGOFF_X5,  20     # t0 (Temporary)
    .equ REGOFF_X6,  24     # t1 (Temporary)
    .equ REGOFF_X7,  28     # t2 (Temporary)
    .equ REGOFF_X8,  32     # s0/fp (Saved Register / Frame Pointer)
    .equ REGOFF_X9,  36     # s1 (Saved Register)
    .equ REGOFF_X10, 40     # a0 (Function Argument / Return Value)
    .equ REGOFF_X11, 44     # a1 (Function Argument / Buffer Pointer)
    .equ REGOFF_X12, 48     # a2 (Function Argument / Message Length)
    .equ REGOFF_X13, 52     # a3 (Function Argument)
    .equ REGOFF_X14, 56     # a4 (Function Argument)
    .equ REGOFF_X15, 60     # a5 (Function Argument)
    .equ REGOFF_X16, 64     # a6 (Function Argument)
    .equ REGOFF_X17, 68     # a7 (Function Argument / Syscall ID)
    .equ REGOFF_X18, 72     # s2 (Saved Register)
    .equ REGOFF_X19, 76     # s3 (Saved Register)
    .equ REGOFF_X20, 80     # s4 (Saved Register)
    .equ REGOFF_X21, 84     # s5 (Saved Register)
    .equ REGOFF_X22, 88     # s6 (Saved Register)
    .equ REGOFF_X23, 92     # s7 (Saved Register)
    .equ REGOFF_X24, 96     # s8 (Saved Register)
    .equ REGOFF_X25, 100    # s9 (Saved Register)
    .equ REGOFF_X26, 104    # s10 (Saved Register)
    .equ REGOFF_X27, 108    # s11 (Saved Register)
    .equ REGOFF_X28, 112    # t3 (Temporary)
    .equ REGOFF_X29, 116    # t4 (Temporary)
    .equ REGOFF_X30, 120    # t5 (Temporary)
    .equ REGOFF_X31, 124    # t6 (Temporary)
    .equ REGOFF_MEPC, 128   # Machine Exception Program Counter (Resume Address)
    .equ REGOFF_MSTATUS, 132 # Machine Status Register (Privilege Mode)
    .equ PROCESS_STATE, 136 # State of the process (READY/WAITING/TERMINATED)
    