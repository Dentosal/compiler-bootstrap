; Convert a 64-bit integer `rdx` to a hex string written to `rdi`.
int_to_str:
    push rax

    std
    add rdi, 15
%rep 16
    mov al, dl
    and rax, 0xf
    mov al, [lookup + rax]
    stosb
    shr rdx, 4
%endrep
    cld

    pop rax
    ret

lookup: db "0123456789abcdef"