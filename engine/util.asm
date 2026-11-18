; ============================================================================
; util.asm  -  small reusable helpers used by every other module
; ----------------------------------------------------------------------------
; All procedures are STDCALL and preserve every register except EAX, ECX and
; EDX only where noted. They never print.
; ============================================================================
INCLUDE stego.inc

.code

; ----------------------------------------------------------------------------
; Util_ReadLE16 : read a 16-bit little-endian value from a buffer
;   In : pBuf = start of buffer, offs = byte offset
;   Out: EAX  = the value (zero-extended)
; Note: BMP files and x86 are both little-endian, so this is a plain load.
;       The procedure exists so callers read like "ReadLE16(buf, 28)".
; ----------------------------------------------------------------------------
Util_ReadLE16 PROC USES esi,
    pBuf:PTR BYTE, offs:DWORD

    mov    esi, pBuf
    add    esi, offs
    movzx  eax, WORD PTR [esi]     ; zero-extend 16 -> 32 bits
    ret
Util_ReadLE16 ENDP

; ----------------------------------------------------------------------------
; Util_ReadLE32 : read a 32-bit little-endian value from a buffer
;   In : pBuf = start of buffer, offs = byte offset
;   Out: EAX  = the value
; ----------------------------------------------------------------------------
Util_ReadLE32 PROC USES esi,
    pBuf:PTR BYTE, offs:DWORD

    mov    esi, pBuf
    add    esi, offs
    mov    eax, DWORD PTR [esi]    ; unaligned reads are fine on x86
    ret
Util_ReadLE32 ENDP

; ----------------------------------------------------------------------------
; Util_WriteLE32 : store a 32-bit value into a buffer (little-endian)
;   In : pBuf, offs, value
;   Out: nothing (used later for the hidden-message length field)
; ----------------------------------------------------------------------------
Util_WriteLE32 PROC USES eax esi,
    pBuf:PTR BYTE, offs:DWORD, value:DWORD

    mov    esi, pBuf
    add    esi, offs
    mov    eax, value
    mov    DWORD PTR [esi], eax
    ret
Util_WriteLE32 ENDP

; ----------------------------------------------------------------------------
; Util_MemCopy : copy 'count' bytes from pSrc to pDest
;   Buffers must NOT overlap. Uses REP MOVSB (forward copy).
; ----------------------------------------------------------------------------
Util_MemCopy PROC USES ecx esi edi,
    pDest:PTR BYTE, pSrc:PTR BYTE, count:DWORD

    cld                            ; direction flag = forward
    mov    edi, pDest
    mov    esi, pSrc
    mov    ecx, count
    rep movsb                      ; copy ECX bytes from [ESI] to [EDI]
    ret
Util_MemCopy ENDP

; ----------------------------------------------------------------------------
; Util_MemZero : fill 'count' bytes at pDest with zero
;   Uses REP STOSB (stores AL into [EDI], ECX times).
; ----------------------------------------------------------------------------
Util_MemZero PROC USES eax ecx edi,
    pDest:PTR BYTE, count:DWORD

    cld
    mov    edi, pDest
    mov    ecx, count
    xor    eax, eax                ; AL = 0
    rep stosb
    ret
Util_MemZero ENDP

; ----------------------------------------------------------------------------
; Util_TrimPath : clean a typed path IN PLACE
;   Removes leading/trailing spaces and double quotes, so a path pasted with
;   Windows "Copy as path" ("C:\x\a.bmp") works. Also removes CR/LF at the end.
;   In : pStr = zero-terminated string (edited in place)
;   Out: nothing
; ----------------------------------------------------------------------------
Util_TrimPath PROC USES eax ecx esi edi,
    pStr:PTR BYTE

    mov    esi, pStr
    mov    edi, esi
t_find_end:                        ; EDI -> terminating zero
    cmp    BYTE PTR [edi], 0
    je     t_trim_tail
    inc    edi
    jmp    t_find_end

t_trim_tail:                       ; cut trailing space / quote / CR / LF
    cmp    edi, esi
    je     t_lead                  ; string is now empty
    mov    al, [edi-1]
    cmp    al, ' '
    je     t_cut
    cmp    al, '"'
    je     t_cut
    cmp    al, 0Dh
    je     t_cut
    cmp    al, 0Ah
    je     t_cut
    jmp    t_lead
t_cut:
    dec    edi
    mov    BYTE PTR [edi], 0
    jmp    t_trim_tail

t_lead:                            ; ECX = first character that is kept
    mov    ecx, esi
t_lead_loop:
    mov    al, [ecx]
    cmp    al, ' '
    je     t_skip
    cmp    al, '"'
    je     t_skip
    jmp    t_shift
t_skip:
    inc    ecx
    jmp    t_lead_loop

t_shift:                           ; move the kept text to the start
    cmp    ecx, esi
    je     t_done                  ; nothing was skipped
t_copy:
    mov    al, [ecx]
    mov    [esi], al
    inc    ecx
    inc    esi
    test   al, al                  ; copy includes the terminating zero
    jnz    t_copy
t_done:
    ret
Util_TrimPath ENDP

; ----------------------------------------------------------------------------
; Util_StrCat : append the text at pSrc to the end of the text at pDest
;   pDest must have room for both texts plus the terminating zero.
; ----------------------------------------------------------------------------
Util_StrCat PROC USES eax,
    pDest:PTR BYTE, pSrc:PTR BYTE

    INVOKE Str_length, pDest       ; EAX = length of the existing text
    add    eax, pDest              ; EAX -> its terminating zero
    INVOKE Str_copy, pSrc, eax     ; copy the new text over that zero
    ret
Util_StrCat ENDP

; ----------------------------------------------------------------------------
; Util_UIntToStr : write an unsigned number as decimal text + terminating zero
;   In : pDest = buffer (at least 11 bytes), value
;   Out: EAX   = number of digits written
; Method: repeatedly divide by 10; the remainders come out last-digit-first,
;         so they are pushed on the stack and popped back in the right order.
; ----------------------------------------------------------------------------
Util_UIntToStr PROC USES ebx ecx edx esi edi,
    pDest:PTR BYTE, value:DWORD

    mov    eax, value
    mov    edi, pDest
    mov    ebx, 10
    xor    ecx, ecx                ; ECX counts the digits
u_div:
    xor    edx, edx
    div    ebx                     ; EAX = quotient, EDX = remainder (0..9)
    add    edx, '0'                ; remainder -> ASCII digit
    push   edx
    inc    ecx
    test   eax, eax
    jnz    u_div
    mov    esi, ecx                ; remember the digit count for the result
u_pop:
    pop    edx
    mov    [edi], dl
    inc    edi
    dec    ecx
    jnz    u_pop
    mov    BYTE PTR [edi], 0       ; terminating zero
    mov    eax, esi
    ret
Util_UIntToStr ENDP

; ----------------------------------------------------------------------------
; Util_Put2 : write value (0..99) as exactly two digits, e.g. 7 -> "07"
;   No terminating zero is written (used to build date/time text).
; ----------------------------------------------------------------------------
Util_Put2 PROC USES eax ecx edx edi,
    pDest:PTR BYTE, value:DWORD

    mov    eax, value
    xor    edx, edx
    mov    ecx, 10
    div    ecx                     ; EAX = tens digit, EDX = ones digit
    add    eax, '0'
    add    edx, '0'
    mov    edi, pDest
    mov    [edi], al
    mov    [edi+1], dl
    ret
Util_Put2 ENDP

END
