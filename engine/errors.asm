; ============================================================================
; errors.asm  -  human-readable text for every engine error code
; ----------------------------------------------------------------------------
; The engine never prints, but it can hand out a pointer to a message so the
; CLI and the GUI show identical wording.
; ============================================================================
INCLUDE stego.inc

.data
msg00 BYTE "OK.",0
msg01 BYTE "Could not open the file.",0
msg02 BYTE "Not a BMP file (missing 'BM' signature).",0
msg03 BYTE "Unsupported BMP: only 24-bit images are supported.",0
msg04 BYTE "Unsupported BMP: compressed images are not supported.",0
msg05 BYTE "Invalid or truncated BMP (bad dimensions or file size).",0
msg06 BYTE "File is too large (limit is 8 MB).",0
msg07 BYTE "The message is too long for this image.",0
msg08 BYTE "No hidden message found (signature missing).",0
msg09 BYTE "The hidden message length is invalid.",0
msg10 BYTE "CRC mismatch: the hidden data is CORRUPTED.",0
msg11 BYTE "Could not write the file.",0
msg12 BYTE "Could not read the file.",0
msg13 BYTE "Invalid image slot number.",0
msg14 BYTE "No image is loaded.",0
msg15 BYTE "The message is empty.",0
msg16 BYTE "The output buffer is too small for the hidden message.",0
msg17 BYTE "The two images must have the same width and height.",0
msg18 BYTE "The log file is empty or does not exist.",0
msg19 BYTE "The log file is full (64 KB). Back it up or clear it.",0
msg20 BYTE "The output file must be different from the cover image.",0
msgUnknown BYTE "Unknown error code.",0

; Table of pointers, indexed by error code (4 bytes per entry).
errTable DWORD OFFSET msg00, OFFSET msg01, OFFSET msg02, OFFSET msg03
         DWORD OFFSET msg04, OFFSET msg05, OFFSET msg06, OFFSET msg07
         DWORD OFFSET msg08, OFFSET msg09, OFFSET msg10, OFFSET msg11
         DWORD OFFSET msg12, OFFSET msg13, OFFSET msg14, OFFSET msg15
         DWORD OFFSET msg16, OFFSET msg17, OFFSET msg18, OFFSET msg19
         DWORD OFFSET msg20

.code

; ----------------------------------------------------------------------------
; Stego_ErrorText
;   In : errCode = an ERR_xxx value
;   Out: EAX = pointer to a zero-terminated message (never NULL)
; ----------------------------------------------------------------------------
Stego_ErrorText PROC,
    errCode:DWORD

    mov    eax, errCode
    cmp    eax, ERR_COUNT
    jae    e_unknown               ; unsigned compare: also catches huge values
    mov    eax, errTable[eax*4]    ; look the pointer up in the table
    ret
e_unknown:
    mov    eax, OFFSET msgUnknown
    ret
Stego_ErrorText ENDP

END
