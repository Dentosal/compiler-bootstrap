%define FLAG_MACRO_INIT     1 ; The next token is the macro name, and body starts after
%define FLAG_MACRO_BODY     2 ; The current token is compiled into the current macro
%define FLAG_ADDROF_NAME    4 ; The next token is a name to be resolved

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
    add_builtin_op addrof
    add_builtin_op zero
    add_builtin_op drop
    add_builtin_op swap
    add_builtin_op pick
    add_builtin_op roll
    add_builtin_op inc
    add_builtin_op dec
    add_builtin_op add
    add_builtin_op mul
    add_builtin_op div
    add_builtin_op shr
    add_builtin_op shl
    add_builtin_op not
    add_builtin_op and
    add_builtin_op or
    add_builtin_op xor
    add_builtin_op eq
    add_builtin_op lt
    add_builtin_op call
    add_builtin_op ccall
    add_builtin_op return
    add_builtin_op creturn
    add_builtin_op ptr_read_u8
    add_builtin_op ptr_read_u16
    add_builtin_op ptr_read_u32
    add_builtin_op ptr_read_u64
    add_builtin_op ptr_write_u8
    add_builtin_op ptr_write_u16
    add_builtin_op ptr_write_u32
    add_builtin_op ptr_write_u64
    add_builtin_op syscall
    add_builtin_op output_file_fd
    add_builtin_op debug
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

    push_many rdi, rcx, r11

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

    pop_many rdi, rcx, r11

    ; Match interpreter state
    mov rax, [r13 + state.flags]
    test rax, FLAG_MACRO_INIT
    jnz .initalize_macro_mode
    test rax, FLAG_MACRO_BODY
    jnz .add_to_macro
    test rax, FLAG_ADDROF_NAME
    jnz .push_addrof_name

    jmp .lookup_and_execute_token

; Start defining a new macro with the current token as the name
.initalize_macro_mode:
    dbg "Defining a new macro"

    ; TODO: check if the command already exists and error out if it does

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
    ; Command entry header: function code pointer, just after the header
    mov [r12], rdi
    ; Next free byte: just after the header (used to append code)
    mov r12, rdi
    pop rcx
    pop rdi
    pop rsi

    ; Flip the init flag off
    mov rax, [r13 + state.flags]
    xor rax, FLAG_MACRO_INIT
    xor rax, FLAG_MACRO_BODY
    mov [r13 + state.flags], rax

    ; Done
    jmp .done


.add_to_macro:
    dbg "Adding to the current macro"

    ; Special case: addrof is resolved immediately
    test rax, FLAG_ADDROF_NAME ; rax still contains flags
    jnz .add_to_macro_addrof

    ; Resolve current macro entry
    call last_command   ; rax = *last_command
    mov rax, [rax]      ; Deref so that rax points to the command header

    ; Special case handling
    cmp rcx, 1
    jne .add_to_macro_add ; Normal case, since all special tokens are 1 byte long
    cmp byte [r11], ';'
    je .end_macro_body
    cmp byte [r11], '\'
    je .set_addrof_mode

    jmp .add_to_macro_add ; Normal case

.set_addrof_mode:
    dbg "Setting addrof mode"

    ; Set flag
    mov rax, [r13 + state.flags]
    or rax, FLAG_ADDROF_NAME
    mov [r13 + state.flags], rax

    jmp .done

.end_macro_body:
    ; Add ret instruction to the end
    mov [r12], byte 0xc3
    inc r12

    dbg "End of macro body"

    ; Finalize macro header with code len field
    mov rcx, r12
    sub rcx, [rax + command_header.code_ptr]
    mov [rax + command_header.code_len], rcx

    ; End macro mode
    mov rax, [r13 + state.flags]
    xor rax, FLAG_MACRO_BODY
    mov [r13 + state.flags], rax

    jmp .done


.add_to_macro_add:
    ; TODO: optimize: inline the function under some conditions

    ; Resolve the function to add
    mov rdi, r11
    call lookup_command ; rax = pointer to command header
    jc .command_not_found

    ; Generate an instruction to call the function
    mov [r12], byte 0x48 ; REX.W
    inc r12
    mov [r12], byte 0xb8 ; https://www.felixcloutier.com/x86/mov.html MOV r64, imm64
    inc r12
    mov rbx, [rax + command_header.code_ptr]
    mov qword [r12], rbx ; code pointer
    add r12, 8
    ; https://www.felixcloutier.com/x86/call.html call near, absolute indirect
    mov [r12], byte 0xff ; Call opcode
    inc r12
    mov [r12], byte 0xd0 ; ModR/M byte: mod=0b00 (register indirect addressing), reg=0b010 (= /2), m=0b000 (rax)
    inc r12

    jmp .done

.add_to_macro_addrof:
    dbg "Adding addrof to the current macro"

    ; Resolve the name
    mov rdi, r11
    call lookup_command  ; rax = command header code pointer
    jc .command_not_found

    ; Generate an instruction to push the address of the function to the stack
    ; sub r15, 8
    mov [r12], byte 0x49 ; REX.W + REX.B
    inc r12
    mov [r12], byte 0x83 ; https://www.felixcloutier.com/x86/sub.html SUB r/m64, imm8
    inc r12
    mov [r12], byte 0xef ; ModR/M byte: mod=0b11 (register direct addressing), reg=0b101 (= /5), r/m=0b111 (r15)
    inc r12
    mov [r12], byte 0x08 ; imm8 = 0x8
    inc r12
    ; mov rax, ADDR_OF_FUNCTION
    mov [r12], byte 0x48 ; REX.W
    inc r12
    mov [r12], byte 0xb8 ; https://www.felixcloutier.com/x86/mov.html MOV r64, imm64
    inc r12
    mov qword [r12], rax ; code pointer
    add r12, 8
    ; mov rax, [rax]
    mov [r12], byte 0x48 ; REX.W
    inc r12
    mov [r12], byte 0x8b ; https://www.felixcloutier.com/x86/mov.html MOV r64, r/m64
    inc r12
    mov [r12], byte 0x00 ; ModR/M byte: mod=0b11 (register indirect addressing), reg=0b000 (= /rax), r/m=0b000 (rax)
    inc r12
    ; mov [r15], rax
    mov [r12], byte 0x49 ; REX.W + REX.B
    inc r12
    mov [r12], byte 0x89 ; https://www.felixcloutier.com/x86/mov.html MOV r/m64, r64
    inc r12
    mov [r12], byte 0x07 ; ModR/M byte: mod=0b11 (register indirect addressing), reg=0b000 (= /rax), r/m=0b111 (r15)
    inc r12

    ; End escaped mode
    mov rax, [r13 + state.flags]
    xor rax, FLAG_ADDROF_NAME
    mov [r13 + state.flags], rax

    jmp .done

.lookup_and_execute_token:
    dbg "Lookup"

    mov rdi, r11
    call lookup_command
    jc .command_not_found

    dbg "Found, execute"

    ; Execute the command
    call [rax + command_header.code_ptr]

    dbg "Returned"

    jmp .done

.push_addrof_name:
    dbg "Lookup name and push addr"

    mov rdi, r11
    call lookup_command
    jc .command_not_found

    dbg "Found, push ptr"

    mov rax, [rax + command_header.code_ptr]
    ds_push rax

    ; End escaped mode
    mov rax, [r13 + state.flags]
    xor rax, FLAG_ADDROF_NAME
    mov [r13 + state.flags], rax

    jmp .done

.command_not_found:
    pop_many rax, rbx, rcx, rdx, rsi, rdi, r8, r9, r10, r11

    ; Prepend the error message with the token
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

; Lookup a command by name ptr=rdi,len=rcx.
; Returns rax=ptr on success.
; Sets carry flag on not found.
lookup_command:
    push_many rbx, rdx, rsi

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

    ; Compare lengths
    cmp rdx, rcx
    jne .traverse_next ; Len mismatch

    ; Obtain name ptr
    mov rsi, rbx
    add rsi, command_header.name_offset

    ; Compare strings
    push_many rcx, rdi
    repe cmpsb
    pop_many rcx, rdi
    jnz .traverse_next ; Mismatch

    mov rax, rbx
    jmp .done

.traverse_not_found: ; Name resolution failed
    stc
.done:
    pop_many rbx, rdx, rsi
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
