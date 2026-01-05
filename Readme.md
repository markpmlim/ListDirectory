### Perform a directory listing with the syscall getdirentries64

<br />
<br />

**Overview:**

The kernel syscall **getdirentries**

    int getdirentries(int fd, char *buf, int nbytes, long *basep);

is deprecated and replaced with 

    user_ssize_t getdirentries64(int fd, void *buf, user_size_t bufsize, off_t *position);

The C library functions

    syscall(int number, ...) and int __syscall(quad_t number, ...);
    
are also deprecated as of macOS 10.12.

This barebones demo shows how to use the kernel syscall **getdirentries64** from within an assembly language program.

<br />
<br />

**Details**

To execute the kernel syscall **getdirentries64**, the file directory must be opened with the kernel syscall

    int open(const char *path, int flags, int mode);

**getdirentries64** requires a *buffer* to be passed as one of its parameters.  On return, a number of dir entry records are read into this buffer; the register rax holds the number of bytes read into the buffer. Given below is the layout of a dir entry record.

<br />
<br />


    struct dirent {                 // when _DARWIN_FEATURE_64_BIT_INODE is defined
        ino_t      d_ino;           // file number of entry (8 bytes)
        __uint64_t d_seekoff;       // seek offset (optional, used by servers) (8 bytes)
        __uint16_t d_reclen;        // length of this record (2 bytes)
        __uint16_t d_namlen;        // length of string in d_name (2 bytes)
        __uint8_t  d_type;          // file type, see below (1 byte)
        char       d_name[1024];    // name must be no longer than this  - padded to 4-byte boundary
    };


The size of this buffer should not be too small because the **maximum** size of a directory entry record is **1048** bytes. Obviously, it will be a sheer waste of valuable memory if the size of each directory entry record returned is fixed at 1048. Instead, the macOS kernel will return the minimum neccessary to encapsulate all information. The actual size of  last field, **d_name**, varies from 1 to 1023 excluding the null terminator. In other words, the sizes of each direntry record read into the buffer may differ. For the "." or ".." directory entries, their sizes are 32 bytes.

The reader can experiment by setting the **bufferSize** equate to 256. In this case, the demo may perform several reads into the buffer, each time printing the number of bytes read into **buffer**.

Given below is a sample memory dump after reading 224 bytes into a 256-byte buffer.

Number of bytes read: 224
(lldb) p &buffer
(void **) $0 = 0x0000000100001050
(lldb) x -c256 0x0000000100001050
0x100001050: 09 d5 76 00 00 00 00 00 00 00 00 00 00 00 00 00  ..v.............
0x100001060: 20 00 01 00 04 2e 00 00 00 00 00 00 00 00 00 00   ...............
0x100001070: 90 2a 09 00 00 00 00 00 00 00 00 00 00 00 00 00  .*..............
0x100001080: 20 00 02 00 04 2e 2e 00 00 00 00 00 00 00 00 00   ...............
0x100001090: 0a f4 79 00 00 00 00 00 00 00 00 00 00 00 00 00  ..y.............
0x1000010a0: 28 00 0a 00 08 49 6e 70 75 74 31 2e 74 78 74 00  (....Input1.txt.
0x1000010b0: 00 00 00 00 00 00 00 00 36 e7 79 00 00 00 00 00  ........6.y.....
0x1000010c0: 00 00 00 00 00 00 00 00 28 00 09 00 08 63 61 6c  ........(....cal
0x1000010d0: 6c 73 75 6d 2e 73 00 00 00 00 00 00 00 00 00 00  lsum.s..........
0x1000010e0: 18 f4 79 00 00 00 00 00 00 00 00 00 00 00 00 00  ..y.............
0x1000010f0: 28 00 0a 00 08 49 6e 70 75 74 30 2e 74 78 74 00  (....Input0.txt.
0x100001100: 00 00 00 00 00 00 00 00 74 e7 7b 00 00 00 00 00  ........t.{.....
0x100001110: 00 00 00 00 00 00 00 00 28 00 0a 00 08 70 72 69  ........(....pri
0x100001120: 6e 74 64 69 72 2e 63 00 00 00 00 00 00 00 00 00  ntdir.c.........
0x100001130: 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00  ................
0x100001140: 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00  ................

The first dirent record starts at the beginning of the buffer at 0x100001050. The value at offset 0x10 (**d_reclen**) is 0x0020 which is 32. This value will be used to compute the buffer offset to the next dirent. The 2 next bytes at record offset 0x12 is 01 00 is the value of **d_namlen**. These are followed by a single byte ( 0x04) which is the value of **d_type** (DT_DIR). The **d_name** is just 0x2e 00 (the dot directory).

The second dirent record starts at 0x100001070 (0x100001050 + 0x0020). This is the double-dot (..) directory. And the third dirent record is 0x100001070 + 0x0020 = 0x100001090 since the value at 0x100001080 (**d_reclen** of previous dirent record) is 0x0020. The value at 0x1000010a0 (offset 0x10 from the start of this dirent record) is 0x0028 (40). This is the **d_reclen** of the third dirent record. The 2 bytes (0a 00) that followed is the **d_namelen** of this dirent record. The single byte value following value is 0x08 indicating this is a regular file (DT_REG). The rest of the bytes is a null-terminated char string "Input1.txt".

The fourth direntry record starts at  0x100001090 + 0x28 = 0x1000010b8 with the bytes "36 e7 79 00 00 00 00 00" (0x000000000079e736) which is the **d_ino** value. The reader will have to check out the rest of the direntries. Please note that the directory being listed should consists of more than a few direntries, preferrably 10-20.

**getdirentries64** keeps track of the number of directory entries read by writing into the variable **posn**. When all dirent records have been read, the kernel syscall writes the value 0x7fffffff into this quad word storage area.

According to information found on the Internet, C functions calls like readdir(DIR *dirp) actually calls an internal kernel call **__getdirentries64**.

<br />
<br />

**Notes**

There are 2 ways to run this demo.

1) Copy the file **listdir** to a desktop folder and compile it using a command line prompt:

    gcc listdir.s -o listdir

 Then execute 
 
    ./listdir . or ./listdir path_to_dir


2) Open the scheme editor of this project and enter the **full** pathname of a directory within the desktop folder.

![](Documentation/ArgumentsPassed.png)

Set breakpoints by clicking on the gutter next to one or more code lines. and then run.

All entries of the table *arguments passed on launch* had been removed from the uploaded project.

<br />
<br />

**Resources**

1) man page of getdirentries

2) the interface file *sys/dirent.h*.

3) https://healeycodes.com/maybe-the-fastest-disk-usage-program-on-macos

