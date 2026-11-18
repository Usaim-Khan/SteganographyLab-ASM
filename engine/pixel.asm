; ============================================================================
; pixel.asm  -  addressing of colour bytes inside the BMP pixel data
; ----------------------------------------------------------------------------
; A 24-bit BMP row holds width*3 colour bytes, followed by 0-3 padding bytes so
; that every row starts on a 4-byte boundary. Hiding, extracting and comparing
; must SKIP the padding. This file is the ONLY place that knows about it:
; every other module asks Pix_Index for "colour byte number n".
; ============================================================================
INCLUDE stego.inc

.code

; ----------------------------------------------------------------------------
; Pix_Index : file offset of the n-th colour byte (n counts from 0, padding
;             bytes are not counted)
;   In : pInfo = BMPINFO of a loaded image
;        n     = colour byte number, 0 .. biColourBytes-1
;   Out: EAX   = offset from the START OF THE LOADED FILE (add biBuffer to get
;                a pointer), or PIX_INVALID if n is out of range
;
; Formula:  row    = n / rowBytes
;           col    = n mod rowBytes
;           offset = dataOffset + row*rowStride + col
; Example (width 5): rowBytes = 15, rowStride = 16, dataOffset = 54
;           n = 14 -> row 0, col 14 -> 68
;           n = 15 -> row 1, col  0 -> 54 + 16 = 70   (offset 69 is padding)
; Works for bottom-up and top-down BMPs: rows are stored one after another
; in both cases, so the same formula applies.
; ----------------------------------------------------------------------------
Pix_Index PROC USES ebx ecx edx,
    pInfo:PTR BMPINFO, n:DWORD

    mov    ebx, pInfo
    mov    eax, n
    cmp    eax, [ebx].BMPINFO.biColourBytes
    jae    x_out_of_range          ; unsigned: n >= total colour bytes

    xor    edx, edx                ; DIV divides EDX:EAX, so clear EDX first
    div    [ebx].BMPINFO.biRowBytes   ; EAX = row, EDX = column
    mov    ecx, edx                ; keep the column (MUL overwrites EDX)
    mul    [ebx].BMPINFO.biRowStride  ; EAX = row * rowStride
    add    eax, ecx                ; + column
    add    eax, [ebx].BMPINFO.biDataOffset
    ret

x_out_of_range:
    mov    eax, PIX_INVALID
    ret
Pix_Index ENDP

; ----------------------------------------------------------------------------
; LSB steganography in one picture:
;   one hidden BYTE  ->  8 consecutive colour bytes, one bit per colour byte.
;   Hidden byte number k uses colour bytes 8k .. 8k+7, most significant bit
;   first. Changing the lowest bit of a colour byte changes its value by at
;   most 1 (out of 255), which the eye cannot see.
; ----------------------------------------------------------------------------

; ----------------------------------------------------------------------------
; Pix_EmbedByte : hide one byte in the LSBs of 8 colour bytes
;   In : pInfo   = BMPINFO of a loaded image
;        byteIdx = hidden byte number k (0 = first byte of the packet)
;        value   = the byte to hide (low 8 bits used)
;   Out: EAX     = ERR_OK, or ERR_BAD_SIZE if the image is too small
; ----------------------------------------------------------------------------
Pix_EmbedByte PROC USES ebx esi edi,
    pInfo:PTR BMPINFO, byteIdx:DWORD, value:DWORD

    LOCAL bitNo:DWORD               ; 0..7 = which of the 8 bits (0 = MSB)

    mov    esi, pInfo
    mov    ebx, byteIdx
    shl    ebx, 3                   ; EBX = first colour byte number = k * 8
    mov    bitNo, 0
e_loop:
    cmp    bitNo, 8
    jae    e_done

    mov    eax, ebx
    add    eax, bitNo               ; colour byte number 8k + bitNo
    INVOKE Pix_Index, esi, eax      ; EAX = its offset in the file buffer
    cmp    eax, PIX_INVALID
    je     e_fail

    mov    edi, [esi].BMPINFO.biBuffer
    add    edi, eax                 ; EDI -> that colour byte in memory

    mov    ecx, 7
    sub    ecx, bitNo               ; CL = 7 - bitNo = position of the bit to hide
    mov    eax, value
    shr    eax, cl                  ; bring that bit to bit 0
    and    eax, 1                   ; AL = 0 or 1
    mov    dl, [edi]
    and    dl, 0FEh                 ; clear the colour byte's lowest bit
    or     dl, al                   ; put our bit there
    mov    [edi], dl

    inc    bitNo
    jmp    e_loop
e_done:
    xor    eax, eax                 ; ERR_OK
    ret
e_fail:
    mov    eax, ERR_BAD_SIZE
    ret
Pix_EmbedByte ENDP

; ----------------------------------------------------------------------------
; Pix_ExtractByte : read back one hidden byte from 8 colour bytes
;   In : pInfo, byteIdx (same numbering as Pix_EmbedByte)
;   Out: EAX = the byte (0..255), or PIX_INVALID if the image is too small
; ----------------------------------------------------------------------------
Pix_ExtractByte PROC USES ebx esi edi,
    pInfo:PTR BMPINFO, byteIdx:DWORD

    LOCAL bitNo:DWORD
    LOCAL result:DWORD

    mov    esi, pInfo
    mov    ebx, byteIdx
    shl    ebx, 3                   ; first colour byte number
    mov    bitNo, 0
    mov    result, 0
x_loop:
    cmp    bitNo, 8
    jae    x_done

    mov    eax, ebx
    add    eax, bitNo
    INVOKE Pix_Index, esi, eax
    cmp    eax, PIX_INVALID
    je     x_fail

    mov    edi, [esi].BMPINFO.biBuffer
    movzx  eax, BYTE PTR [edi + eax]   ; the colour byte
    and    eax, 1                      ; its lowest bit
    mov    edx, result
    shl    edx, 1                      ; make room for the new bit (MSB first)
    or     edx, eax
    mov    result, edx

    inc    bitNo
    jmp    x_loop
x_done:
    mov    eax, result
    ret
x_fail:
    mov    eax, PIX_INVALID
    ret
Pix_ExtractByte ENDP

END
