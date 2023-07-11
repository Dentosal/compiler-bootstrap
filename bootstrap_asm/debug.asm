; Generates function that prints message and exits with error code
%macro dbg 1
%ifndef nostack
    push_all
%endif

    mov rax, 1      ; write
    mov rdi, 1      ; stdout
    mov rsi, %%msg ; message
    mov rdx, %%len ; message length
    syscall
    js exit

%ifndef nostack
    pop_all
%endif

    jmp %%over
%ifdef nobreak
%%msg: db %1
%else
%%msg: db %1, 10
%endif
%%len: equ $ - %%msg
%%over:
%endmacro

%macro dbg_nobreak 1
%define nobreak
    dbg %1
%undef nobreak
%endmacro

; Dumps register value
%macro dbg_int 1
    push_all

    mov rdx, %1

    call alloc_page ; rax = buffer
    push rax

    mov rdi, rax
    call int_to_str

    mov rsi, rax    ; message
    mov rdx, 16     ; message length
    mov rax, 1      ; write
    mov rdi, 1      ; stdout
    syscall
    js error_misc

    mov rax, 1      ; write
    mov rdi, 1      ; stdout
    mov rsi, linebreak
    mov rdx, 1
    syscall
    js error_misc

    pop rdi
    call free_page

    pop_all
%endmacro

