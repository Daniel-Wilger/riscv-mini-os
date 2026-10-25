# ==============================================================================
# USER CONFIGURATION (config.inc)
# ==============================================================================
# Any changes here scale the system without breaking the core logic.

.equ TRAP_FRAME_SHIFT,      8       # 2^8 = 256 bytes per Trap Frame
.equ TRAP_FRAME_SIZE,       (1 << TRAP_FRAME_SHIFT) # Automatically evaluates to 256

# --- IPC Settings ---
.equ SHARED_BUFFER_LEN,      10     # Capacity of the shared buffer

# --- Process Configuration ---
.equ INITIAL_PROCESS_COUNT,   2     # Number of processes the OS starts with (e.g., A and B)

# --- User Process Settings ---
.equ USER_BUFFER_LENGTH,     32

.macro GET_USER_A_MSG
    .ascii "Hello World"
.endm
