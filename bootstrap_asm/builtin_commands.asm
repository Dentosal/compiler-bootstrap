; Token interpreter operations

; Pop from data stack into register
%macro ds_pop 1
    mov %1, [r15]
    add r15, 8
%endmacro

; Push register onto data stack
%macro ds_push 1
    sub r15, 8
    mov [r15], %1
%endmacro

; Define a command, with optional rename to allow non-nasm-identifier names
%macro def 1-2
%push fndef
builtin_%1:
%$header:
    dq %$code
    dq %$code_len
    dq %$name_len
%$name:
%if %0 == 2
%define stringified %2
%else
%defstr stringified %1
%endif
    db stringified
%$name_len: equ $ - %$name
%$code:
%endmacro

%macro endef 0
%$code_len: equ $ - %$code
%pop fndef
%endmacro

; == Special operations ==

def startmacro, ":"
    push rax

    ; Read flags
    mov rax, [r13 + state.flags]
    ; If we're already in a macro, error
    ; ^ TODO: this cannot be called, that should be handled in the compile-mode interpreter function
    test rax, FLAG_MACRO_INIT
    jnz error_macro_nesting
    test rax, FLAG_MACRO_BODY
    jnz error_macro_nesting
    ; Set macro mode
    or rax, FLAG_MACRO_INIT
    mov [r13 + state.flags], rax

    pop rax
    ret
endef

; This is not a real command, as it only works in macro mode.
; In normal execution, it will always error.
def endmacro, ";"
    jmp error_endmacro_outside
endef


def addrof ; get address of a function by name

    ; Set flag
    mov rax, [r13 + state.flags]
    or rax, FLAG_ADDROF_NAME
    mov [r13 + state.flags], rax

    ret
endef


; == Stack operations ==

def zero
    sub r15, 8
    mov qword [r15], 0
    ret
endef

def drop
    add r15, 8
    ret
endef

def swap
    push rax
    mov rax, [r15]
    xchg rax, [r15 + 8]
    mov [r15], rax
    pop rax
    ret
endef

def pick ; pick nth item from stack
    push rax
    ds_pop rax
    mov rax, [r15 + 8 * rax]
    ds_push rax
    pop rax
    ret
endef

def roll ; roll nth item to top of stack, moving everything above it down
    push_many rax, rcx, rsi, rdi
    ds_pop rcx
    test rcx, rcx
    jz .skip
    mov rax, [r15 + 8 * rcx] ; save the nth item
    lea rsi, [r15 + 8 * rcx]
    mov rdi, rsi
    sub rsi, 8
    std ; reverse direction
    rep movsq
    cld
    mov [r15], rax
.skip:
    pop_many rax, rcx, rsi, rdi
    ret
endef

; == Arithmetic and logic ==

def inc
    inc qword [r15]
    ret
endef

def dec
    dec qword [r15]
    ret
endef

def add
    push_many rax, rbx
    ds_pop rbx
    ds_pop rax
    add rax, rbx
    ds_push rax
    pop_many rax, rbx
    ret
endef

def mul
    push_many rax, rdx
    ds_pop rdx
    ds_pop rax
    mul rdx
    ds_push rax
    pop_many rax, rdx
    ret
endef

def div
    push_many rax, rdx
    ds_pop rdx
    ds_pop rax
    div rdx
    ds_push rax
    pop_many rax, rdx
    ret
endef

def shr
    push_many rax, rcx
    ds_pop rcx
    ds_pop rax
    shr rax, cl
    ds_push rax
    pop_many rax, rcx
    ret
endef

def shl
    push_many rax, rcx
    ds_pop rcx
    ds_pop rax
    shl rax, cl
    ds_push rax
    pop_many rax, rcx
    ret
endef

def not
    not qword [rsp]
    ret
endef

def and
    push_many rax, rdx
    ds_pop rdx
    ds_pop rax
    and rax, rdx
    ds_push rax
    pop_many rax, rdx
    ret
endef

def or
    push_many rax, rdx
    ds_pop rax
    ds_pop rdx
    or rax, rdx
    ds_push rax
    pop_many rax, rdx
    ret
endef

def xor
    push_many rax, rdx
    ds_pop rdx
    ds_pop rax
    xor rax, rdx
    ds_push rax
    pop_many rax, rdx
    ret
endef

def eq
    push_many rax, rdx
    ds_pop rdx
    ds_pop rax
    cmp rax, rdx
    mov rax, 0
    jne .false
    inc rax
.false:
    ds_push rax
    pop_many rax, rdx
    ret
endef

def lt
    push_many rax, rdx
    ds_pop rdx
    ds_pop rax
    cmp rax, rdx
    mov rax, 0
    jge .false
    inc rax
.false:
    ds_push rax
    pop_many rax, rdx
    ret
endef

; == Control flow ==

def call ; call a function by pointer
    push rax
    ds_pop rax
    call rax
    pop rax
    ret
endef

def ccall ; conditional call
    push_many rax, rbx
    ds_pop rax
    ds_pop rbx
    test rbx, rbx
    pop rbx
    jz .skip
    call rax
.skip:
    pop rax
    ret
endef

def return ; early return from macro context
    add rsp, 16
    pop rax
    ret
endef

def creturn ; conditional early return from macro context
    push rax
    ds_pop rax
    test rax, rax
    jz .skip
    add rsp, 24
.skip:
    pop rax
    ret
endef

; == Raw memory access ==

def ptr_read_u8
    push rax
    ds_pop rax
    xor rax, rax
    mov al, [rax]
    ds_push rax
    pop rax
    ret
endef

def ptr_read_u16
    push rax
    ds_pop rax
    xor rax, rax
    mov ax, [rax]
    ds_push rax
    pop rax
    ret
endef

def ptr_read_u32
    push rax
    ds_pop rax
    xor rax, rax
    mov eax, [rax]
    ds_push rax
    pop rax
    ret
endef

def ptr_read_u64
    push rax
    ds_pop rax
    mov rax, [rax]
    ds_push rax
    pop rax
    ret
endef

def ptr_write_u8
    push_many rax, rbx
    ds_pop rax ; value
    ds_pop rbx ; address
    mov [rbx], al
    pop_many rax, rbx
    ret
endef

def ptr_write_u16
    push_many rax, rbx
    ds_pop rax ; value
    ds_pop rbx ; address
    mov [rbx], ax
    pop_many rax, rbx
    ret
endef

def ptr_write_u32
    push_many rax, rbx
    ds_pop rax ; value
    ds_pop rbx ; address
    mov [rbx], eax
    pop_many rax, rbx
    ret
endef

def ptr_write_u64
    push_many rax, rbx
    ds_pop rax ; value
    ds_pop rbx ; address
    mov [rbx], rax
    pop_many rax, rbx
    ret
endef

; == System calls ==

def syscall
    push_many rax, rdi, rsi, rdx, r10, r8, r9
    ds_pop r9
    ds_pop r8
    ds_pop r10
    ds_pop rdx
    ds_pop rsi
    ds_pop rdi
    ds_pop rax
    syscall
    ds_push rax
    pop_many rax, rdi, rsi, rdx, r10, r8, r9
    ret
endef

def output_file_fd ; Compilation output file
    ds_pop r9
    ret
endef

; == Debugging and dev utils ==

def show
    dbg_int [r15]
    ret
endef

def commands
    push_all
%define nostack
    dbg "Dumping commands"
%undef nostack

    ; Lookup token from a linked list starting from
    mov rax, [r13 + state.oplist]
    jmp .traverse_lookup
.traverse_next:
    mov rax, [rax + 8] ; Link to next item
    cmp rax, 0
    je .traverse_done
.traverse_lookup:
    mov rbx, [rax]
    mov rdx, [rbx + command_header.name_len] ; Name len

    ; Obtain name ptr
    mov rsi, rbx
    add rsi, 24

    ; Print name
    dbg_nobreak "  "
    push rax
    mov rax, 1      ; write
    mov rdi, 1      ; stdout
    syscall
    js exit
    dbg ""          ; Newline
    pop rax

    jmp .traverse_next

.traverse_done:
    dbg "End of listing"

    pop_all
    ret
endef