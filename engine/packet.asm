; ============================================================================
; packet.asm  -  the hidden packet: signature, length, message, CRC-32
; ----------------------------------------------------------------------------
; Packet layout (hidden byte numbers, see pixel.asm for how bytes are hidden):
;    0.. 3   signature 'S','T','G','1'  (tells us a message is present)
;    4.. 7   message length, little-endian
;    8..8+L-1  the message bytes
;   8+L..11+L  CRC-32 of the message, little-endian
; Overhead = 12 bytes, so   capacity = (colour bytes / 8) - 12.
; ============================================================================
INCLUDE stego.inc

.data
sigBytes   BYTE 'S','T','G','1'    ; the 4-byte signature

.code

; ----------------------------------------------------------------------------
; Pkt_Capacity : largest message (in bytes) an image can hold
;   In : pInfo   Out: EAX = capacity (0 if the image is too small)
; ----------------------------------------------------------------------------
Pkt_Capacity PROC USES ebx,
    pInfo:PTR BMPINFO

    mov    ebx, pInfo
    mov    eax, [ebx].BMPINFO.biColourBytes
    shr    eax, 3                   ; hidden bytes available = colour bytes / 8
    cmp    eax, PKT_OVERHEAD
    jbe    k_zero                   ; no room for even a 1-byte message
    sub    eax, PKT_OVERHEAD
    ret
k_zero:
    xor    eax, eax
    ret
Pkt_Capacity ENDP

; ----------------------------------------------------------------------------
; Pkt_EmbedDword (internal) : hide a 32-bit value as 4 bytes, little-endian
;   In : pInfo, pos = first hidden byte number, value      Out: EAX = error
; ----------------------------------------------------------------------------
Pkt_EmbedDword PROC USES ebx,
    pInfo:PTR BMPINFO, pos:DWORD, value:DWORD

    LOCAL i:DWORD

    mov    i, 0
d_loop:
    cmp    i, 4
    jae    d_done
    mov    ecx, i
    shl    ecx, 3                   ; 8 * i
    mov    eax, value
    shr    eax, cl                  ; bring byte i of the value down to AL
    and    eax, 0FFh
    mov    ebx, pos
    add    ebx, i                   ; hidden byte number pos + i
    INVOKE Pix_EmbedByte, pInfo, ebx, eax
    test   eax, eax
    jnz    d_ret                    ; error: pass it up
    inc    i
    jmp    d_loop
d_done:
    xor    eax, eax
d_ret:
    ret
Pkt_EmbedDword ENDP

; ----------------------------------------------------------------------------
; Pkt_ReadDword (internal) : read a hidden 32-bit little-endian value
;   In : pInfo, pos = first hidden byte number, pValue = where to store it
;   Out: EAX = error (ERR_BAD_SIZE if the image is too small)
; ----------------------------------------------------------------------------
Pkt_ReadDword PROC USES ebx,
    pInfo:PTR BMPINFO, pos:DWORD, pValue:PTR DWORD

    LOCAL i:DWORD
    LOCAL val:DWORD

    mov    i, 0
    mov    val, 0
r_loop:
    cmp    i, 4
    jae    r_done
    mov    ebx, pos
    add    ebx, i
    INVOKE Pix_ExtractByte, pInfo, ebx
    cmp    eax, PIX_INVALID
    je     r_fail
    mov    ecx, i
    shl    ecx, 3                   ; 8 * i
    shl    eax, cl                  ; put the byte at position i of the value
    or     val, eax
    inc    i
    jmp    r_loop
r_done:
    mov    edx, pValue
    mov    eax, val
    mov    [edx], eax
    xor    eax, eax
    ret
r_fail:
    mov    eax, ERR_BAD_SIZE
    ret
Pkt_ReadDword ENDP

; ----------------------------------------------------------------------------
; Pkt_ReadHeader : check the signature and read the message length
;   In : pInfo, pLen = where to store the length
;   Out: EAX = ERR_OK, ERR_NO_SIG (image too small or signature missing) or
;              ERR_BAD_LENGTH (length is 0 or larger than the image can hold)
; Shared by Extract, Verify and Analyze.
; ----------------------------------------------------------------------------
Pkt_ReadHeader PROC USES ebx esi,
    pInfo:PTR BMPINFO, pLen:PTR DWORD

    LOCAL cap:DWORD
    LOCAL msgLen:DWORD
    LOCAL i:DWORD

    INVOKE Pkt_Capacity, pInfo
    mov    cap, eax
    test   eax, eax
    jz     h_no_sig                 ; image too small to hold any packet

    mov    i, 0
h_sig_loop:                         ; compare the 4 hidden bytes with "STG1"
    cmp    i, 4
    jae    h_sig_ok
    INVOKE Pix_ExtractByte, pInfo, i
    mov    ecx, i
    movzx  edx, sigBytes[ecx]
    cmp    eax, edx
    jne    h_no_sig
    inc    i
    jmp    h_sig_loop
h_sig_ok:

    INVOKE Pkt_ReadDword, pInfo, 4, ADDR msgLen
    test   eax, eax
    jnz    h_no_sig
    mov    eax, msgLen
    test   eax, eax
    jz     h_bad_len                ; a message cannot be empty
    cmp    eax, cap
    ja     h_bad_len                ; claims more bytes than the image holds
    mov    edx, pLen
    mov    [edx], eax
    xor    eax, eax                 ; ERR_OK
    ret
h_no_sig:
    mov    eax, ERR_NO_SIG
    ret
h_bad_len:
    mov    eax, ERR_BAD_LENGTH
    ret
Pkt_ReadHeader ENDP

; ----------------------------------------------------------------------------
; Pkt_Hide : hide a message in the image held in a slot (edits it in memory;
;            save it afterwards with Bmp_Save)
;   In : slot, pMsg = message bytes, msgLen = number of bytes
;   Out: EAX = ERR_OK, ERR_BAD_SLOT, ERR_NOT_LOADED, ERR_EMPTY_MSG or
;              ERR_MSG_TOO_BIG
; ----------------------------------------------------------------------------
Pkt_Hide PROC USES ebx esi,
    slot:DWORD, pMsg:PTR BYTE, msgLen:DWORD

    LOCAL pInfo:DWORD
    LOCAL crc:DWORD
    LOCAL pos:DWORD

    INVOKE Bmp_Check, slot, ADDR pInfo
    test   eax, eax
    jnz    hd_ret

    cmp    msgLen, 0
    je     hd_empty
    INVOKE Pkt_Capacity, pInfo
    cmp    msgLen, eax
    ja     hd_too_big               ; message longer than the capacity

    INVOKE Crc_Compute, pMsg, msgLen  ; CRC of the message, hidden at the end
    mov    crc, eax
    mov    pos, 0                   ; next hidden byte number

    ; ---- 1. signature ----
    xor    ebx, ebx
hd_sig:
    cmp    ebx, 4
    jae    hd_sig_done
    movzx  eax, sigBytes[ebx]
    INVOKE Pix_EmbedByte, pInfo, pos, eax
    test   eax, eax
    jnz    hd_ret
    inc    pos
    inc    ebx
    jmp    hd_sig
hd_sig_done:

    ; ---- 2. length (4 bytes) ----
    INVOKE Pkt_EmbedDword, pInfo, pos, msgLen
    test   eax, eax
    jnz    hd_ret
    add    pos, 4

    ; ---- 3. the message itself ----
    mov    esi, pMsg
    mov    ebx, msgLen              ; EBX = bytes still to hide
hd_msg:
    test   ebx, ebx
    jz     hd_msg_done
    movzx  eax, BYTE PTR [esi]
    INVOKE Pix_EmbedByte, pInfo, pos, eax
    test   eax, eax
    jnz    hd_ret
    inc    pos
    inc    esi
    dec    ebx
    jmp    hd_msg
hd_msg_done:

    ; ---- 4. CRC-32 (4 bytes) ----
    INVOKE Pkt_EmbedDword, pInfo, pos, crc
    ret                             ; EAX = ERR_OK or the error from above

hd_empty:
    mov    eax, ERR_EMPTY_MSG
    ret
hd_too_big:
    mov    eax, ERR_MSG_TOO_BIG
hd_ret:
    ret
Pkt_Hide ENDP

; ----------------------------------------------------------------------------
; Pkt_Extract : read the hidden message out of the image in a slot
;   In : slot, pOut = buffer for the message, maxOut = its size in bytes,
;        pOutLen = receives the message length (may be NULL)
;   Out: EAX = ERR_OK, ERR_NO_SIG, ERR_BAD_LENGTH or ERR_BUF_SMALL
;        The text is zero-terminated, so maxOut must be at least length + 1.
; The CRC is NOT checked here; use Pkt_Verify for that.
; ----------------------------------------------------------------------------
Pkt_Extract PROC USES ebx edi,
    slot:DWORD, pOut:PTR BYTE, maxOut:DWORD, pOutLen:PTR DWORD

    LOCAL pInfo:DWORD
    LOCAL msgLen:DWORD

    INVOKE Bmp_Check, slot, ADDR pInfo
    test   eax, eax
    jnz    ex_ret
    INVOKE Pkt_ReadHeader, pInfo, ADDR msgLen
    test   eax, eax
    jnz    ex_ret

    mov    eax, msgLen
    inc    eax                      ; message + terminating zero
    cmp    eax, maxOut
    ja     ex_small

    mov    edi, pOut
    xor    ebx, ebx                 ; EBX = message byte index
ex_loop:
    cmp    ebx, msgLen
    jae    ex_done
    lea    eax, [ebx + 8]           ; message starts at hidden byte number 8
    INVOKE Pix_ExtractByte, pInfo, eax
    mov    [edi + ebx], al
    inc    ebx
    jmp    ex_loop
ex_done:
    mov    BYTE PTR [edi + ebx], 0  ; terminating zero
    mov    edx, pOutLen
    test   edx, edx
    jz     ex_ok
    mov    eax, msgLen
    mov    [edx], eax
ex_ok:
    xor    eax, eax
    ret
ex_small:
    mov    eax, ERR_BUF_SMALL
ex_ret:
    ret
Pkt_Extract ENDP

; ----------------------------------------------------------------------------
; Pkt_Verify : recompute the CRC-32 of the hidden message and compare it with
;              the CRC stored in the image
;   In : slot, pVI = VERIFYINFO to fill (length, stored CRC, calculated CRC)
;   Out: EAX = ERR_OK            (VALID)
;              ERR_CRC_BAD       (CORRUPTED; pVI is still filled in)
;              ERR_NO_SIG / ERR_BAD_LENGTH / slot errors
; The message is read byte by byte straight from the image, so no buffer is
; needed: each byte is fed into the running CRC with Crc_UpdateByte.
; ----------------------------------------------------------------------------
Pkt_Verify PROC USES ebx,
    slot:DWORD, pVI:PTR VERIFYINFO

    LOCAL pInfo:DWORD
    LOCAL msgLen:DWORD
    LOCAL crc:DWORD
    LOCAL stored:DWORD

    INVOKE Bmp_Check, slot, ADDR pInfo
    test   eax, eax
    jnz    v_ret
    INVOKE Pkt_ReadHeader, pInfo, ADDR msgLen
    test   eax, eax
    jnz    v_ret

    mov    crc, 0FFFFFFFFh          ; initial CRC value
    xor    ebx, ebx                 ; EBX = message byte index
v_loop:
    cmp    ebx, msgLen
    jae    v_loop_done
    lea    eax, [ebx + 8]
    INVOKE Pix_ExtractByte, pInfo, eax
    INVOKE Crc_UpdateByte, crc, eax
    mov    crc, eax
    inc    ebx
    jmp    v_loop
v_loop_done:
    not    crc                      ; final XOR: crc now = calculated CRC-32

    mov    ebx, msgLen
    add    ebx, 8                   ; the stored CRC follows the message
    ; (EBX, not EAX, carries the position: INVOKE uses EAX to build ADDR stored)
    INVOKE Pkt_ReadDword, pInfo, ebx, ADDR stored
    test   eax, eax
    jnz    v_ret

    mov    edx, pVI                 ; report all three values to the caller
    mov    eax, msgLen
    mov    [edx].VERIFYINFO.viMsgLen, eax
    mov    eax, stored
    mov    [edx].VERIFYINFO.viStoredCrc, eax
    mov    eax, crc
    mov    [edx].VERIFYINFO.viCalcCrc, eax

    cmp    eax, stored
    jne    v_corrupt
    xor    eax, eax                 ; ERR_OK = VALID
    ret
v_corrupt:
    mov    eax, ERR_CRC_BAD
v_ret:
    ret
Pkt_Verify ENDP

END
