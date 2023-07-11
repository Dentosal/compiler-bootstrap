; nasm -f bin -o bootstrap bootstrap.asm && chmod +x bootstrap && ./bootstrap input output

bits 64
org 0x400000

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
.empty_token:
    inc rsi
    loop .for_char_in_buffer
    jmp .loop

.eof:

    mov rdi, 0 ; success
    jmp exit


; #### Token interpreter ####

; Initializes interpreter tokens to r12 memory area

%include "ops.asm"

%macro add_ti_op 1
    add r12, 16
    mov qword [r12 - 16], ti_%1
    mov qword [r12 - 8], r12
%endmacro

init_interpreter:
    ; Builtin operations
    add_ti_op zero
    add_ti_op inc
    add_ti_op drop
    add_ti_op swap
    add_ti_op dup
    add_ti_op show
    ; Clear the last link, so that the linked list ends here
    mov qword [r12 - 8], 0
    ret

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


    ; Debug print token name before executing
    dbg_nobreak "Executing token: "

    mov rcx, rdi
    sub rcx, r11
    push rdi
    push rcx

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

    pop rcx
    pop rdi


    ; Lookup token from a linked list starting from
    mov rax, r13
    jmp .traverse_lookup
.traverse_next:
    mov rax, [rax + 8] ; Link to next item
    cmp rax, 0
    je .traverse_not_found
.traverse_lookup:
    mov rbx, [rax]
    mov rdx, [rbx + 16] ; Name len

    cmp rdx, rcx    ; Len mismatch?
    jne .traverse_next

    ; Obtain name ptr
    mov rsi, rbx
    add rsi, 24

    ; Compare to name at r11
    mov rdi, r11
    push rcx
    repe cmpsb
    pop rcx
    jnz .traverse_next ; Mismatch

    ; Found the token, call the function
    call [rbx]

    dbg "Done executing token"

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

.traverse_not_found: ; Name resolution failed
    ; Prefix the error message with the token
    mov rcx, rdi
    sub rcx, r11

    mov rax, 1      ; write
    mov rdi, 1      ; stdout
    mov rsi, r11    ; message
    mov rdx, rcx    ; message length
    syscall

    jmp error_unknown_token


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
usage:                  error   "usage: bootstrap input output"
error_mmap_buffer:      error   "error: could not allocate buffer"
error_munmap:           error   "error: could not free buffer"
error_open_input:       error   "error: could not open input file"
error_read_input:       error   "error: could not read input file"
error_open_output:      error   "error: could not open output file"
error_write_output:     error   "error: could not write output file"
error_unknown_token:    error   ": error: unable to resolve name"

; Exits with return code from rdi
exit:
    mov rax, 60       ; exit
    syscall

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
    push rdi
    push rsi
    push rdx
    push r10
    push r9
    push r8

    mov rax, 11             ; munmap
    mov rsi, 4096           ; page size
    xor r8, r8
    xor r9, r9
    syscall                 ; rax = address
    cmp rax, -1
    je error_munmap

    pop r8
    pop r9
    pop r10
    pop rdx
    pop rsi
    pop rdi
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

; #### Helper constants ####

; https://gist.github.com/Zhangerr/6022492
fileFlagsInput  equ 0o0000   ; create file + read and write mode
fileFlagsOutput equ 0o1102   ; create file + read and write mode
fileMode        equ 0o0600   ; user has read write permission

filesize equ $ - $$
