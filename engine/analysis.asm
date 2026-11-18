; ============================================================================
; analysis.asm  -  analyse one image, compare two images (x87 FPU for PSNR)
; ----------------------------------------------------------------------------
; Both procedures walk the pixel rows directly (row start = buffer + data
; offset + row * stride) so the padding bytes at the end of each row are
; skipped for free.  In a 24-bit BMP each pixel is stored as Blue, Green, Red.
; ============================================================================
INCLUDE stego.inc

.data
const65025 DWORD 65025             ; 255 * 255, the peak signal squared
const10    REAL8 10.0              ; PSNR = 10 * log10(...)

.code

; ----------------------------------------------------------------------------
; An_Analyze : header facts, capacity and simple statistics of one image
;   In : slot, pAI = ANALYSISINFO to fill
;   Out: EAX = ERR_OK, ERR_BAD_SLOT or ERR_NOT_LOADED
; Statistics: mean of the blue / green / red values, how many colour bytes
; have their lowest bit set, and whether a hidden message header is present.
; ----------------------------------------------------------------------------
An_Analyze PROC USES ebx esi edi,
    slot:DWORD, pAI:PTR ANALYSISINFO

    LOCAL pInfo:DWORD
    LOCAL sumB:DWORD
    LOCAL sumG:DWORD
    LOCAL sumR:DWORD
    LOCAL ones:DWORD
    LOCAL row:DWORD
    LOCAL msgLen:DWORD

    INVOKE Bmp_Check, slot, ADDR pInfo
    test   eax, eax
    jnz    an_ret
    INVOKE Util_MemZero, pAI, SIZEOF ANALYSISINFO

    ; ---- 1. facts copied from the BMPINFO -------------------------------------
    mov    ebx, pInfo
    mov    edi, pAI
    mov    eax, [ebx].BMPINFO.biWidth
    mov    [edi].ANALYSISINFO.aiWidth, eax
    mov    eax, [ebx].BMPINFO.biHeight
    mov    [edi].ANALYSISINFO.aiHeight, eax
    mov    eax, [ebx].BMPINFO.biBitCount
    mov    [edi].ANALYSISINFO.aiBitCount, eax
    mov    eax, [ebx].BMPINFO.biFileSize
    mov    [edi].ANALYSISINFO.aiFileSize, eax
    mov    eax, [ebx].BMPINFO.biDataOffset
    mov    [edi].ANALYSISINFO.aiDataOffset, eax
    mov    eax, [ebx].BMPINFO.biRowStride
    mov    [edi].ANALYSISINFO.aiRowStride, eax
    mov    eax, [ebx].BMPINFO.biColourBytes
    mov    [edi].ANALYSISINFO.aiColourBytes, eax
    mov    eax, [ebx].BMPINFO.biWidth
    mul    [ebx].BMPINFO.biHeight           ; EAX = width * height = pixel count
    mov    [edi].ANALYSISINFO.aiPixelCount, eax
    INVOKE Pkt_Capacity, ebx
    mov    [edi].ANALYSISINFO.aiCapacity, eax

    ; ---- 2. scan every pixel -----------------------------------------------------
    mov    sumB, 0
    mov    sumG, 0
    mov    sumR, 0
    mov    ones, 0
    mov    row, 0
an_row:
    mov    ebx, pInfo
    mov    eax, row
    cmp    eax, [ebx].BMPINFO.biHeight
    jae    an_scan_done
    mul    [ebx].BMPINFO.biRowStride        ; EAX = row * stride
    add    eax, [ebx].BMPINFO.biDataOffset
    add    eax, [ebx].BMPINFO.biBuffer
    mov    esi, eax                         ; ESI -> first pixel of this row
    mov    ecx, [ebx].BMPINFO.biWidth       ; pixels in the row
an_px:
    movzx  eax, BYTE PTR [esi]              ; blue
    add    sumB, eax
    and    eax, 1                           ; lowest bit: 0 or 1
    add    ones, eax
    movzx  eax, BYTE PTR [esi + 1]          ; green
    add    sumG, eax
    and    eax, 1
    add    ones, eax
    movzx  eax, BYTE PTR [esi + 2]          ; red
    add    sumR, eax
    and    eax, 1
    add    ones, eax
    add    esi, 3                           ; next pixel
    dec    ecx
    jnz    an_px
    inc    row
    jmp    an_row
an_scan_done:

    ; ---- 3. averages (sum / pixel count; a sum fits in 32 bits for <= 8 MB) ----
    mov    edi, pAI
    mov    ecx, [edi].ANALYSISINFO.aiPixelCount
    mov    eax, sumB
    xor    edx, edx
    div    ecx
    mov    [edi].ANALYSISINFO.aiAvgB, eax
    mov    eax, sumG
    xor    edx, edx
    div    ecx
    mov    [edi].ANALYSISINFO.aiAvgG, eax
    mov    eax, sumR
    xor    edx, edx
    div    ecx
    mov    [edi].ANALYSISINFO.aiAvgR, eax
    mov    eax, ones
    mov    [edi].ANALYSISINFO.aiLsbOnes, eax

    ; ---- 4. is a hidden message present? ----------------------------------------
    INVOKE Pkt_ReadHeader, pInfo, ADDR msgLen
    test   eax, eax
    jnz    an_ok                            ; no header: aiHasMessage stays 0
    mov    edi, pAI
    mov    [edi].ANALYSISINFO.aiHasMessage, 1
    mov    eax, msgLen
    mov    [edi].ANALYSISINFO.aiMsgLen, eax
an_ok:
    xor    eax, eax                         ; ERR_OK
an_ret:
    ret
An_Analyze ENDP

; ----------------------------------------------------------------------------
; An_Compare : compare an original and an encoded image byte by byte
;   In : slotA (original), slotB (encoded), pCI = COMPAREINFO to fill
;   Out: EAX = ERR_OK, slot errors, or ERR_SIZE_MISMATCH
; Reports changed bytes, changed bits, the largest difference, the sum of
; squared differences (64-bit), MSE and PSNR:
;       MSE  = sum((a-b)^2) / number of colour bytes
;       PSNR = 10 * log10(255^2 / MSE)  dB      (images identical: MSE = 0)
; Since LSB hiding changes a byte by at most 1, expect MSE <= 1 and PSNR >= 48.
; ----------------------------------------------------------------------------
An_Compare PROC USES ebx esi edi,
    slotA:DWORD, slotB:DWORD, pCI:PTR COMPAREINFO

    LOCAL pA:DWORD
    LOCAL pB:DWORD
    LOCAL row:DWORD
    LOCAL changedBytes:DWORD
    LOCAL changedBits:DWORD
    LOCAL maxDiff:DWORD
    LOCAL sumLo:DWORD
    LOCAL sumHi:DWORD

    INVOKE Bmp_Check, slotA, ADDR pA
    test   eax, eax
    jnz    cp_ret
    INVOKE Bmp_Check, slotB, ADDR pB
    test   eax, eax
    jnz    cp_ret

    ; ---- the two images must have the same width and height --------------------
    mov    ebx, pA
    mov    edx, pB
    mov    eax, [ebx].BMPINFO.biWidth
    cmp    eax, [edx].BMPINFO.biWidth
    jne    cp_mismatch
    mov    eax, [ebx].BMPINFO.biHeight
    cmp    eax, [edx].BMPINFO.biHeight
    jne    cp_mismatch

    INVOKE Util_MemZero, pCI, SIZEOF COMPAREINFO
    mov    changedBytes, 0
    mov    changedBits, 0
    mov    maxDiff, 0
    mov    sumLo, 0
    mov    sumHi, 0
    mov    row, 0

cp_row:
    mov    ebx, pA
    mov    eax, row
    cmp    eax, [ebx].BMPINFO.biHeight
    jae    cp_rows_done
    mul    [ebx].BMPINFO.biRowStride
    add    eax, [ebx].BMPINFO.biDataOffset
    add    eax, [ebx].BMPINFO.biBuffer
    mov    esi, eax                         ; ESI -> row in the original
    mov    ebx, pB
    mov    eax, row
    mul    [ebx].BMPINFO.biRowStride
    add    eax, [ebx].BMPINFO.biDataOffset
    add    eax, [ebx].BMPINFO.biBuffer
    mov    edi, eax                         ; EDI -> row in the encoded image
    mov    ebx, pA
    mov    ecx, [ebx].BMPINFO.biRowBytes    ; colour bytes in this row

cp_byte:
    movzx  eax, BYTE PTR [esi]              ; a = original
    movzx  edx, BYTE PTR [edi]              ; b = encoded
    cmp    eax, edx
    je     cp_same
    inc    changedBytes
    mov    ebx, eax
    xor    ebx, edx                         ; EBX = the bits that differ
    sub    eax, edx                         ; a - b (may be negative)
    jns    cp_pos
    neg    eax
cp_pos:                                     ; EAX = |a - b|, 1..255
    cmp    eax, maxDiff
    jbe    cp_nomax
    mov    maxDiff, eax
cp_nomax:
    mul    eax                              ; EDX:EAX = diff * diff
    add    sumLo, eax                       ; 64-bit running sum: add the low
    adc    sumHi, 0                         ;   half, carry into the high half
cp_bits:                                    ; count the 1-bits in EBX
    test   ebx, ebx
    jz     cp_same
    mov    eax, ebx
    dec    eax
    and    ebx, eax                         ; clears the lowest set bit
    inc    changedBits
    jmp    cp_bits
cp_same:
    inc    esi
    inc    edi
    dec    ecx
    jnz    cp_byte
    inc    row
    jmp    cp_row

cp_rows_done:
    ; ---- fill the result ---------------------------------------------------------
    mov    edi, pCI
    mov    ebx, pA
    mov    eax, [ebx].BMPINFO.biWidth
    mov    [edi].COMPAREINFO.ciWidth, eax
    mov    eax, [ebx].BMPINFO.biHeight
    mov    [edi].COMPAREINFO.ciHeight, eax
    mov    eax, [ebx].BMPINFO.biColourBytes
    mov    [edi].COMPAREINFO.ciColourBytes, eax
    mov    eax, changedBytes
    mov    [edi].COMPAREINFO.ciChangedBytes, eax
    mov    eax, changedBits
    mov    [edi].COMPAREINFO.ciChangedBits, eax
    mov    eax, maxDiff
    mov    [edi].COMPAREINFO.ciMaxDiff, eax
    mov    eax, sumLo
    mov    [edi].COMPAREINFO.ciSumSqLo, eax
    mov    eax, sumHi
    mov    [edi].COMPAREINFO.ciSumSqHi, eax

    cmp    changedBytes, 0
    jne    cp_float
    mov    [edi].COMPAREINFO.ciIdentical, 1 ; no difference: MSE = 0, PSNR = "infinite"
    jmp    cp_ok                            ;   (both stay 0.0 from the MemZero)

    ; ---- MSE and PSNR with the x87 FPU --------------------------------------------
    ; ST(0) is the top of the FPU register stack; comments show the stack
    ; as "ST0, ST1, ..." after each instruction.
cp_float:
    fild   QWORD PTR [edi].COMPAREINFO.ciSumSqLo       ; sum of squares
    fidiv  DWORD PTR [edi].COMPAREINFO.ciColourBytes   ; MSE
    fst    QWORD PTR [edi].COMPAREINFO.ciMse           ; store MSE, keep a copy
    fldlg2                                             ; log10(2), MSE
    fxch                                               ; MSE, log10(2)
    fyl2x                    ; ST1 * log2(ST0)  ->  log10(2)*log2(MSE) = log10(MSE)
    fchs                                               ; -log10(MSE)
    fldlg2                                             ; log10(2), -log10(MSE)
    fild   DWORD PTR const65025                        ; 65025, log10(2), -log10(MSE)
    fyl2x                                              ; log10(65025), -log10(MSE)
    faddp  st(1), st                                   ; log10(65025) - log10(MSE)
    fmul   QWORD PTR const10                           ; times 10  = PSNR in dB
    fstp   QWORD PTR [edi].COMPAREINFO.ciPsnr          ; store, stack is empty again
cp_ok:
    xor    eax, eax                                    ; ERR_OK
    ret
cp_mismatch:
    mov    eax, ERR_SIZE_MISMATCH
cp_ret:
    ret
An_Compare ENDP

END
