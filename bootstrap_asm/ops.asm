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

%macro def 1
%push fndef
ti_%1:
%$header:
    dq %$code
    dq %$code_len
    dq %$name_len
%$name:
%defstr stringified %1
    db stringified
%$name_len: equ $ - %$name
%$code:
%endmacro

%macro endef 0
%$code_len: equ $ - %$code
%pop fndef
%endmacro


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