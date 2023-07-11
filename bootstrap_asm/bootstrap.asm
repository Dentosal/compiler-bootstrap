; nasm -f bin -o bootstrap bootstrap.asm && chmod +x bootstrap && ./bootstrap input output
;
; The following registers hold the compiler state:
; r8: input file fd
; r9: output file fd
; r10: input buffer
; r11: current token buffer
; r12: pointer to next free byte in data buffer
; r13: pointer to interpreter state struct
; r14: interpreter call stack
; r15: interpreter data stack

bits 64
org 0x400000

%include "macros.asm"
%include "debug.asm"

; #### Helper macros ####

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
    mov r10, rax             ; Input buffer
    call alloc_page
    mov r11, rax             ; Token buffer
    call alloc_page
    mov r12, rax             ; This is where data that will not be freed is written
    mov r13, r12             ; This will be constant, while r12 will be incremented

    ; Stacks grow downwards
    call alloc_page
    mov r14, rax             ; Call stack
    add r14, 4096
    call alloc_page
    mov r15, rax             ; Data stack
    add r15, 4096

    ; Initialize interpreter
    call init_interpreter

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
    je .empty_token
    call execute_token
    mov rdi, r11 ; clear token buffer

    ; push_all

    ; mov rsi, r10    ; message
    ; mov rdx, rax     ; message length
    ; mov rax, 1      ; write
    ; mov rdi, 1      ; stdout
    ; syscall

    ; mov rax, 1      ; write
    ; mov rdi, 1      ; stdout
    ; mov rsi, separator
    ; mov rdx, separator_len
    ; syscall

    ; pop_all


.empty_token:
    inc rsi
    loop .for_char_in_buffer
    jmp .loop

.eof:

    mov rdi, 0 ; success
    jmp exit


; #### Error handling ####

%include "error.asm"

; #### Token interpreter ####

%include "interpreter.asm"


; #### Memory management functions ####

; Allocate a buffer of 4096 bytes
; Returns rax = address
alloc_page:
    push rdi
    push rsi
    push rdx
    push r10
    push r9
    push r8

    mov rax, 9              ; mmap
    mov rdi, 0              ; let kernel choose address
    mov rsi, 4096           ; page size
    mov rdx, 3              ; rw
    mov r10, 0x22           ; private anonymous mapping
    xor r8, r8
    xor r9, r9
    syscall                 ; rax = address
    cmp rax, -1
    je error_mmap_buffer

    pop r8
    pop r9
    pop r10
    pop rdx
    pop rsi
    pop rdi
    ret

; Free a buffer pointed by rdi
free_page:
    push_many rdi, rsi, rdx, r10, r9, r8

    mov rax, 11             ; munmap
    mov rsi, 4096           ; page size
    xor r8, r8
    xor r9, r9
    syscall                 ; rax = address
    cmp rax, -1
    je error_munmap

    pop_many r8, r9, r10, rdx, rsi, rdi
    ret

; Store a lenght-prefixed byte array in unfreeable data area (r12)
; Copies the data from the given source. Returns pointer to the length-prefix.
; rsi = pointer to data
; rcx = length
; Returns rcx = pointer to the length-prefix. Trashes rsi.
unfreeable_store_with_len:
    push rdi
    push r12

    mov [r12], rcx
    add r12, 8
    mov rdi, r12
    rep stosb
    mov r12, rdi

    pop rcx
    pop rdi
    ret


; #### String processing functions ####

%include "convert.asm"

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

; Compares two length-prefixed strings, `rsi` and `rdi`.
; Sets carry flag if inequal, clears otherwise.
len_prefixed_eq:
    push rsi
    push rdi
    push rcx

    mov rcx, [rsi]
    cmp rcx, [rdi]
    jne .not_equal

    add rsi, 8
    add rdi, 8

    repe cmpsb
    jne .not_equal

.equal:
    clc
    jmp .over
.not_equal:
    stc
.over:
    pop rcx
    pop rdi
    pop rsi
    ret

; #### String literals ####

linebreak: db 10
separator: db "======================", 10
separator_len: equ $ - separator

; #### Helper constants ####

; https://gist.github.com/Zhangerr/6022492
fileFlagsInput  equ 0o0000   ; create file + read and write mode
fileFlagsOutput equ 0o1102   ; create file + read and write mode
fileMode        equ 0o0600   ; user has read write permission

filesize equ $ - $$
