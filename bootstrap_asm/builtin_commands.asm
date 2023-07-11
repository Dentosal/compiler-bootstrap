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


def startmacro, ":"
    push rax

    ; Read flags
    mov rax, [r13 + state.flags]
    ; If we're already in a macro, error
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

def zero
    sub r15, 8
    mov qword [r15], 0
    ret
endef

def inc
    inc qword [r15]
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

def dup
    push rax
    mov rax, [r15]
    ds_push rax
    pop rax
    ret
endef

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