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
usage:                      error   "usage: bootstrap input output"
error_misc:                 error   "error: error!"
error_mmap_buffer:          error   "error: could not allocate buffer"
error_munmap:               error   "error: could not free buffer"
error_open_input:           error   "error: could not open input file"
error_read_input:           error   "error: could not read input file"
error_open_output:          error   "error: could not open output file"
error_write_output:         error   "error: could not write output file"
error_unknown_token:        error   ": error: unable to resolve name"
error_macro_nesting:        error   "error: cannot nest definitions"
error_endmacro_outside:     error   "error: endmacro (;) outside macro context"
error_miscompiled_token:    error   "error: miscompiled: invalid name generated"

; Exits with return code from rdi
exit:
    mov rax, 60       ; exit
    syscall
