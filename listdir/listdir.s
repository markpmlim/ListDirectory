/* size = 1048
 struct dirent {                // when _DARWIN_FEATURE_64_BIT_INODE is defined
    ino_t      d_fileno;        // file number of entry (8 bytes)
    __uint64_t d_seekoff;       // seek offset (optional, used by servers) (8 bytes)
    __uint16_t d_reclen;        // length of this record (2 bytes)
    __uint16_t d_namlen;        // length of string in d_name (2 bytes)
    __uint8_t  d_type;          // file type, see below (1 byte)
    char       d_name[1024];    // name must be no longer than this  - padded to 4-byte boundary
};
 The size of each dirent struct as declared above is 1048 (0x418) bytes.
 One would expect a call to getdirentries64 would require a buffer size more than 1048.
 However, when the dirent structs are read into memory, they are actually smaller in size because
 the d_name field is likely to be much smaller than 1024 bytes. Minimum size of each dirent struct
 returned is 32 bytes.
 The size of each dirent struct is given by its d_reclen field. Adding this to current buffer offset
 to the beginning of a dirent struct will produce the offset to the start of the next dirent struct.

 */

#define DT_UNKNOWN       0
#define DT_FIFO          1
#define DT_CHR           2
#define DT_DIR           4
#define DT_BLK           6
#define DT_REG           8
#define DT_LNK          10
#define DT_SOCK         12
#define DT_WHT          14

# syscall numbers
sys_exit            = 0x2000000|0x01
sys_read            = 0x2000000|0x03
sys_write           = 0x2000000|0x04        # unused
sys_open            = 0x2000000|0x05
sys_close           = 0x2000000|0x06
sys_getdirentries64 = 0x2000000|0x158       # 344 = 0x158

    .data
# getdirentries64 keeps track of the number of dir entries read here.
# When all dir entries are read, it writes a value of 0x7fffffff here.
posn:
    .quad 0


# Expect the # of bytes read to be a multiple of 16 bytes.
bytes_read_msg:
    .asciz "Number of bytes read: %ld\n"

# format string use to display a dirent's name
entry_name:
    .asciz "%s\n"

    .align 4
bufferSize = 4096
buffer:
    .space bufferSize

    .text
    .globl _main
    .extern _printf
    .p2align 4
# int main(int argc, char *argv[]);
_main:
    # Standard function prologue
    pushq   %rbp
    movq    %rsp, %rbp

    cmpq    $2, %rdi                    # argc == 2?
    jb      abort
    addq    $8, %rsi                    # skip the program name
    movq    (%rsi), %rdi                # pathname of directory

    subq    $64, %rsp                   # Still aligned on 16-byte boundary

# Save some callee-saved registers
    movq    %rbx, -8(%rbp)
    movq    %r12, -16(%rbp)
    movq    %r13, -24(%rbp)
    movq    %r14, -32(%rbp)
    movq    $0, %r14                    # number of dir entries.
    # int open(const char *path, int flags, int mode);
    # pointer to path is already in rdi
    movq    $0, %rsi                    # flags (O_RDONLY)
    movq    $0, %rdx                    # mode (not needed for opening existing file for reading)
    movq    $sys_open, %rax
    syscall

    cmpq    $-1, %rax                   # fd - file descriptor
    je      abort

# Save file descriptor in a local variable on the stack
    movq    %rax, -40(%rbp)

readMore:
    # user_ssize_t getdirentries64(int fd, void *buf, user_size_t bufsize, off_t *posn);
    movq    -40(%rbp), %rdi             # fd
    leaq    buffer(%rip), %rsi          # buf address
    movq    $bufferSize, %rdx           # bufsize
    leaq    posn(%rip), %r10            # syscall will over-write the contents of this variable.
    movq    $sys_getdirentries64, %rax
    syscall

    cmpq    $0, %rax                    # %rax has the number of bytes read
    je      .done
    movq    %rax, -48(%rbp)             # Store bytes read in a local variable

#==== the block of code below can be commented out
    leaq    bytes_read_msg(%rip), %rdi  # format string
    movq    -48(%rbp), %rsi             # # of bytes read
    movb    $0, %al                     # No floating point registers used
    callq   _printf                     # Call the C function printf
#====

    leaq    buffer(%rip), %rbx          # addr of start of buffer area
#   movq    $0, %r12                    # ptr to a directory entry struct
    movq    $0, %r13                    # current buffer_pos at beginning of buffer area
next_entry:
    cmpq    -48(%rbp), %r13             # if current buffer_pos >= # of bytes read
    jge     readMore                    # read more direntry records into buffer area

    incq    %r14
    movq    %r13, %r12                  # r13 has offset into buffer
    addq    %rbx, %r12                  # ptr to direntry = addr of buffer + buffer_pos
    leaq    entry_name(%rip), %rdi      # format string
    leaq    21(%r12), %rsi              # addr of d_name
    movb    $0, %al
    callq   _printf                     # Call C function printf

    addq    $16, %r12                   # offset to d_reclen within dirent record
    movw    (%r12), %ax                 # get the d_reclen
    addq    %rax, %r13                  # update buffer_pos into buffer
    jmp     next_entry

.done:
# int close(int fd);
    movq    -40(%rbp), %rdi             
    movq    $sys_close, %rax
    syscall

# Restore the callee-saved registers
    movq    -32(%rbp), %r14
    movq    -24(%rbp), %r13
    movq    -16(%rbp), %r12
    movq    -8(%rbp), %rbx

# Standard function epilogue
    movq    %rbp, %rsp
    popq    %rbp
    xorq    %rax, %rax                  # exit status code 0
    ret

# KIV - print a message
abort:
    # void exit(int status);
    movq    $1, %rdi                  # exit status code 1
    movq    $sys_exit, %rax
    syscall


