; nasm -f bin -o bootstrap bootstrap.asm && chmod +x bootstrap && ./bootstrap input output

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
    ; Validate argc == 3, print usage otherwise
    mov eax, [rsp]          ; argc
    cmp eax, 3
    jne usage

    ; Use mmap to allocate a buffer
    mov rax, 9              ; mmap
    mov rdi, 0              ; let kernel choose address
    mov rsi, 4096           ; page size
    mov rdx, 3              ; rw
    mov r10, 0x22           ; private anonymous mapping
    syscall                 ; rax = address
    cmp rax, -1
    je error_mmap_buffer
    mov r10, rax             ; keep buffer in r10

    ; Open input file
    mov rdi, [rsp + 16]     ; argv[1]
    mov rax, 2              ; open
    mov rsi, fileFlagsInput ; flags
    mov rdx, fileMode       ; mode
    syscall ; rax = fd
    mov r8, rax             ; keep fd in r8
    test rax, rax
    js error_open_input

    ; Open output file
    mov rdi, [rsp + 24]     ; argv[1]
    mov rax, 2              ; open
    mov rsi, fileFlagsOutput; flags
    mov rdx, fileMode       ; mode
    syscall ; rax = fd
    mov r9, rax             ; keep fd in r9
    test rax, rax
    js error_open_output

    ; Copy input to output
.loop:
    ; Read from file
    mov rax, 0              ; read
    mov rdi, r8             ; fd
    mov rsi, r10            ; buffer at r10
    syscall                 ; rax = bytes read
    test rax, rax
    js error_read_input
    jz .done

    ; Write to file
    mov rdx, rax            ; bytes to write (from output of read)
    mov rax, 1              ; write
    mov rdi, r9             ; fd
    mov rsi, r10            ; buffer at r10
    syscall                 ; rax = bytes written

    jmp .loop
.done:

    mov rdi, 0 ; success
    jmp exit


; #### Error handling ####

; Generates function that prints message and exits with error code
%macro error 1
%%0:
    mov rax, 1     ; write
    mov rdi, 1     ; stdout
    mov rsi, .msg  ; message
    mov rdx, .len  ; message length
    syscall
    mov rdi, 1 ; Error code
    jmp exit

.msg: db %1, 10
.len: equ $ - .msg
%endmacro

; Error messages
usage:              error   "usage: bootstrap input output"
error_mmap_buffer:  error   "error: could not allocate buffer"
error_open_input:   error   "error: could not open input file"
error_read_input:   error   "error: could not read input file"
error_open_output:  error   "error: could not open output file"

; Exits with return code from rdi
exit:
    mov rax, 60       ; exit
    syscall

; #### String processing functions ####

; Get length of null-terminated string pointed by `rdi`.
; Returns length in `rcx`.
; See http://www.int80h.org/strlen/ for inspiration
strlen:
    push rdi
    push ax

	xor	rcx, rcx
	not	rcx
	xor	al, al
	cld
    repne scasb
	not	rcx
	dec	rcx

    pop ax
    pop rdi

    ret

; #### Helper constants ####

; https://gist.github.com/Zhangerr/6022492
fileFlagsInput  equ 0o0000   ; create file + read and write mode
fileFlagsOutput equ 0o1102   ; create file + read and write mode
fileMode        equ 0o0600   ; user has read write permission

filesize equ $ - $$
