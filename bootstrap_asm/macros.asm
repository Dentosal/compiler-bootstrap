; Helper macros

%macro push_many 1-*
%rep %0
    push %1
    %rotate 1
%endrep
%endmacro

%macro pop_many 1-*
%rep %0
    pop %1
    %rotate 1
%endrep
%endmacro

%macro push_all 0
    push_many rax, rbx, rcx, rdx, rsi, rdi, r8, r9, r10, r11, r12, r13, r14, r15
%endmacro

%macro pop_all 0
    pop_many r15, r14, r13, r12, r11, r10, r9, r8, rdi, rsi, rdx, rcx, rbx, rax
%endmacro
