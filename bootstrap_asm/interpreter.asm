%define FLAG_MACRO_INIT 1 ; The next token is the macro name, and body starts after
%define FLAG_MACRO_BODY 2 ; The current token is compiled into the current macro

struc command_header
    .code_ptr: resq 1
    .code_len: resq 1
    .name_len: resq 1
    .name_offset:
endstruc

%include "builtin_commands.asm"

struc state
    ; Pointer to first entry in command list
    .oplist: resq 1
    ; State flags
    .flags: resq 1
    .end:
endstruc

; Pushes a new linked list node to r12 memory area
%macro add_builtin_op 1
    add r12, 16
    mov qword [r12 - 16], builtin_%1
    mov qword [r12 - 8], r12
%endmacro

; Initializes interpreter state including commands to r12 memory area
init_interpreter:
    ; Initialize state
    ; The linked list of commands starts immedately after the header
    mov rax, r12
    add rax, state.end
    mov qword [r12], rax
    ; Set flags to zero
    mov qword [r12 + 8], 0
    ; End the struct
    add r12, state.end

    ; Builtin commands
    add_builtin_op startmacro
    add_builtin_op endmacro
    add_builtin_op zero
    add_builtin_op inc
    add_builtin_op drop
    add_builtin_op swap
    add_builtin_op dup
    add_builtin_op show
    add_builtin_op commands
    ; Clear the last link, so that the linked list ends here
    mov qword [r12 - 8], 0
    ret

; Token at starts at r11 and ends at rdi
execute_token:
    push_many rax, rbx, rcx, rdx, rsi, rdi, r8, r9, r10, r11

    ; Debug print token name before executing
    dbg_nobreak "Received token: "

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

    ; Match interpreter state
    mov rax, [r13 + state.flags]
    dbg_int rax
    test rax, FLAG_MACRO_INIT
    jnz .initalize_macro_mode
    test rax, FLAG_MACRO_BODY
    jnz .add_to_macro

    jmp .lookup_and_execute_token

; Start defining a new macro with the current token as the name
.initalize_macro_mode:
    dbg "Defining a new macro"

    ; Add new entry to the linked list of commands
    call last_command       ; rax = *last_command

    mov [rax + 8], r12      ; Set the next pointer to the new entry
    add r12, 16             ; Allocate a new entry in the linked list
    mov [r12 - 16], r12     ; Pointer to the new command header, just after the LL entry
    mov qword [r12 - 8], 0  ; Null pointer to the next LL entry

    ; Command entry header: code length
    mov qword [r12 + command_header.code_len], 0
    ; Command entry header: name length
    mov [r12 + command_header.name_len], rcx
    ; Command entry header: name, copied from r11 buffer
    push rsi
    push rdi
    push rcx
    mov rsi, r11
    mov rdi, r12
    add rdi, command_header.name_offset
    rep movsb ; Copy name
    pop rcx
    pop rdi
    pop rsi
    ; Command entry header: function code pointer, just after the header
    mov [r12], rdi
    ; Next free byte: just after the header (used to append code)
    mov r12, rdi

    ; Flip the init flag off
    mov rax, [r13 + state.flags]
    xor rax, FLAG_MACRO_INIT
    xor rax, FLAG_MACRO_BODY
    mov [r13 + state.flags], rax

    ; Done
    jmp .done


.add_to_macro:
    dbg "Adding to the current macro"

    call last_command ; rax = *last_command

    ; Deref so that rax points to the command header
    mov rax, [rax]

    ; Now rax points to the last item in the linked list, which is the current macro
    ; TODO: End the macro body if the current token is ";"
    ; TODO: optimize: perform some amount of inlining here

    ; Generate a jump instruction to jump over the invoked function name
    mov [r12], byte 0xe9 ; https://www.felixcloutier.com/x86/jmp.html
    add r12, 1
    mov [r12], ecx       ; Relative jump offset = length of the name
    add r12, 8

    ; Include the actual function name, and set to the end of the macro body after this
    push rcx
    push rdi
    push rsi
    mov rsi, r11
    mov rdi, r12
    rep movsb
    mov r12, rdi
    pop rsi
    pop rdi
    pop rcx

    ; Now r12 points to the target of the generated jump above
    ; Now we generate a instruction to call the function that will execute a token by name
    ; Push rax, since we need to preserve it
    mov [r12], byte 0x50
    inc r12
    ; Set rax to the address of the function to call
    mov [r12], byte 0x48 ; REX.W
    inc r12
    mov [r12], byte 0xb8 ; https://www.felixcloutier.com/x86/mov.html MOV r64, imm64
    inc r12
    mov qword [r12], execute_by_name
    add r12, 8
    ; https://www.felixcloutier.com/x86/call.html call near, absolute indirect
    mov [r12], byte 0xff ; Call opcode
    inc r12
    mov [r12], byte 0xd0 ; ModR/M byte: mod=0b11 (register addressing), reg=0b010 (= /2), m=0b000 (rax)
    inc r12
    ; Pop rax
    mov [r12], byte 0x50
    inc r12

    jmp .done

.lookup_and_execute_token:
    dbg "Executing"

    ; Lookup token from a linked list starting pointed by the header
    mov rax, [r13 + state.oplist]

    jmp .traverse_lookup
    .traverse_next:
        mov rax, [rax + 8] ; Link to next item
        cmp rax, 0
        je .traverse_not_found
    .traverse_lookup:
        mov rbx, [rax]
        mov rdx, [rbx + command_header.name_len]

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

        dbg "Calling"

        ; Found the token, call the function
        call [rbx + command_header.code_ptr]

        dbg "Done executing token"
        jmp .done


    .traverse_not_found: ; Name resolution failed
        pop_many rax, rbx, rcx, rdx, rsi, rdi, r8, r9, r10, r11

        ; Prefix the error message with the token
        mov rcx, rdi
        sub rcx, r11

        mov rax, 1      ; write
        mov rdi, 1      ; stdout
        mov rsi, r11    ; message
        mov rdx, rcx    ; message length
        syscall

        jmp error_unknown_token

.done:
    dbg "Done"

    pop_many rax, rbx, rcx, rdx, rsi, rdi, r8, r9, r10, r11
    ret

; Traverse to the last item in the linked list of commands
; return pointer in `rax`
last_command:
    push rbx
    mov rax, [r13 + state.oplist]
.traverse:
    mov rbx, [rax + 8]
    cmp rbx, 0 ; Link to next item
    je .done
    mov rax, [rax + 8]
    jmp .traverse
.done:
    pop rbx
    ret


; Called by the generated code to execute a token by name
execute_by_name:
    jmp exit