; nasm -f bin -o bootstrap bootstrap.asm && chmod +x bootstrap && ./bootstrap

bits 64
org 0x400000

; #### ELF header ####

elf:
db 0x7F, 'ELF'  ; Magic number
db 2, 1         ; 64-bit little endian
db 1            ; ELF version 1
db 0, 0         ; ABI (none)
times 7 db 0    ; Padding
dw 2            ; Executable file
dw 0x3e         ; x86-64
dd 1            ; ELF version 1
dq _start       ; Entry point
dq 0x40         ; Program header offset
dq 0            ; Section header offset (none)
dd 0            ; Flags (none)
dw 0x40         ; ELF header size
dw 0x38         ; Program header entry size
dw 1            ; Number of program header entries
dw 0x40         ; Section header entry size (none)
dw 0            ; Number of section header entries
dw 0            ; Section header string table (none)

; #### ELF program header ####

phdr:
dd 1            ; Type: LOAD
dd 5            ; Flags: RX
dq 0            ; Offset (just load the whole file)
dq 0x400000     ; Virtual address
dq 0            ; Physical address (unused)
dq filesize     ; Size in file
dq filesize     ; Size in memory
dq 0x1000       ; Alignment

; #### Executable code ####

_start:
  mov rax, 1        ; write(
  mov rdi, 1        ;   STDOUT_FILENO,
  mov rsi, msg      ;   "Hello, world!\n",
  mov rdx, msglen   ;   sizeof("Hello, world!\n")
  syscall           ; );

  mov rax, 60       ; exit(
  mov rdi, 0        ;   EXIT_SUCCESS
  syscall           ; );

msg: db "Hello, world!", 10
msglen: equ $ - msg

filesize equ $ - $$