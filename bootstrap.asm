; nasm -f bin -o bootstrap bootstrap.asm && chmod +x bootstrap && ./bootstrap input output

bits 64
org 0x400000

; #### Helper macros ####


; Generates function that prints message and exits with error code
%macro dbg 1
    push rax
    push rcx
    push rdx
    push rsi
    push rdi
    push r8
    push r9
    push r10
    push r11

    mov rax, 1      ; write
    mov rdi, 1      ; stdout
    mov rsi, %%msg ; message
    mov rdx, %%len ; message length
    syscall

    pop r11
    pop r10
    pop r9
    pop r8
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rax
    jmp %%over

%%msg: db %1, 10
%%len: equ $ - %%msg
%%over:
%endmacro


%macro jmp_if_whitespace 1
    cmp byte [rsi], 0x09 ; \t
    je %1
    cmp byte [rsi], 0x0a ; \n
    je %1
    cmp byte [rsi], 0x0d ; \r
    je %1
    cmp byte [rsi], 0x20 ; space
    je %1
%endmacro

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

; #### Compiler I/O handling ####

_start:
    ; Validate argc == 3, print usage otherwise
    mov eax, [rsp]          ; argc
    cmp eax, 3
    jne usage

    ; Use mmap to allocate some buffers
    call alloc_page
    mov r10, rax             ; Input buffer in r10
    call alloc_page
    mov r11, rax             ; Token buffer in r11

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

    ; Start by writing the ELF header to output, copying from the running binary
    mov rdx, 0x40+0x38      ; bytes to write (ELF header size)
    mov rax, 1              ; write
    mov rdi, r9             ; fd
    mov rsi, 0x400000       ; buffer at r10
    syscall                 ; rax = bytes written
    js error_write_output

    ; Read and compile
.loop:
    ; Read from file
    mov rax, 0              ; read
    mov rdi, r8             ; fd
    mov rsi, r10            ; buffer at r10
    syscall                 ; rax = bytes read
    test rax, rax
    js error_read_input
    jz .eof

    mov rdi, r11    ; pointer to current position in token buffer
    mov rsi, r10    ; pointer to current position in input buffer
    mov rcx, rax    ; loop limit at bytes read

.for_char_in_buffer:
    jmp_if_whitespace .whitespace
    movsb
    loop .for_char_in_buffer
    jmp .loop

.whitespace:
    ; If token buffer is nonempty, execute the token
    cmp rdi, r11
    call execute_token
    mov rdi, r11 ; clear token buffer
    inc rsi
    loop .for_char_in_buffer
    jmp .loop
.eof:

    mov rdi, 0 ; success
    jmp exit


; #### Actual compilation ####

; Token at starts at r11 and ends at rdi
execute_token:
    push rax
    push rcx
    push rdx
    push rsi
    push rdi
    push r8
    push r9
    push r10
    push r11

    mov rcx, rdi
    sub rcx, r11

    mov rax, 1      ; write
    mov rdi, 1      ; stdout
    mov rsi, r11    ; message
    mov rdx, rcx    ; message length
    syscall

    mov rax, 1      ; write
    mov rdi, 1      ; stdout
    mov rsi, linebreak
    mov rdx, 1
    syscall

    pop r11
    pop r10
    pop r9
    pop r8
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rax

    ret

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
error_write_output: error   "error: could not write output file"

; Exits with return code from rdi
exit:
    mov rax, 60       ; exit
    syscall

; #### Memory management functions ####

; Allocate a buffer of 4096 bytes and store address in r10
; Returns rax = address
alloc_page:
    push rdi
    push rsi
    push rdx
    push r10

    mov rax, 9              ; mmap
    mov rdi, 0              ; let kernel choose address
    mov rsi, 4096           ; page size
    mov rdx, 3              ; rw
    mov r10, 0x22           ; private anonymous mapping
    syscall                 ; rax = address
    cmp rax, -1
    je error_mmap_buffer

    pop r10
    pop rdx
    pop rsi
    pop rdi
    ret

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

; #### String literals ####

linebreak: db 10


; #### Helper constants ####

; https://gist.github.com/Zhangerr/6022492
fileFlagsInput  equ 0o0000   ; create file + read and write mode
fileFlagsOutput equ 0o1102   ; create file + read and write mode
fileMode        equ 0o0600   ; user has read write permission

filesize equ $ - $$
