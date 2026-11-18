; ============================================================================
; bmp.asm  -  load, parse and validate 24-bit uncompressed BMP files
; ----------------------------------------------------------------------------
; Two image "slots" exist: SLOT_MAIN (0) and SLOT_SECOND (1, for Compare).
; Each slot owns an 8 MB buffer and a BMPINFO describing the loaded image.
;
; BMP layout used here (all values little-endian):
;   offset  0  2 bytes  signature 'B','M'
;   offset 10  4 bytes  pixel data offset
;   offset 14  4 bytes  info-header size (40 for the common BITMAPINFOHEADER)
;   offset 18  4 bytes  width  (signed)
;   offset 22  4 bytes  height (signed; negative = rows stored top-down)
;   offset 28  2 bytes  bits per pixel
;   offset 30  4 bytes  compression (0 = none)
; ============================================================================
INCLUDE stego.inc

.data?
bmpBuf0   BYTE MAX_BMP_SIZE + 1 DUP(?)   ; +1 lets us detect "file too big"
bmpBuf1   BYTE MAX_BMP_SIZE + 1 DUP(?)
img0      BMPINFO <>                     ; info for slot 0
img1      BMPINFO <>                     ; info for slot 1

.code

; ----------------------------------------------------------------------------
; Bmp_GetInfo : get the BMPINFO of a slot
;   In : slot = SLOT_MAIN or SLOT_SECOND
;   Out: EAX  = pointer to BMPINFO, or 0 if the slot number is invalid.
;        Check [EAX].biBuffer: 0 means no image is loaded in that slot.
; ----------------------------------------------------------------------------
Bmp_GetInfo PROC,
    slot:DWORD

    cmp    slot, SLOT_MAIN
    je     g_main
    cmp    slot, SLOT_SECOND
    je     g_second
    xor    eax, eax                ; invalid slot -> NULL
    ret
g_main:
    mov    eax, OFFSET img0
    ret
g_second:
    mov    eax, OFFSET img1
    ret
Bmp_GetInfo ENDP

; ----------------------------------------------------------------------------
; Bmp_Parse : validate a BMP that is already in memory and fill a BMPINFO
;   In : pBuf     = start of the file bytes
;        fileSize = number of valid bytes in pBuf
;        pInfo    = BMPINFO to fill (written ONLY if validation succeeds)
;   Out: EAX      = ERR_OK or one of
;          ERR_NOT_BMP    no 'BM' signature
;          ERR_BAD_SIZE   truncated header/pixel data, bad dimensions
;          ERR_NOT_24BIT  bits per pixel is not 24
;          ERR_COMPRESSED compression field is not 0
; This procedure does no file I/O, so the GUI can also use it on a buffer.
; ----------------------------------------------------------------------------
Bmp_Parse PROC USES esi edi,
    pBuf:PTR BYTE, fileSize:DWORD, pInfo:PTR BMPINFO

    LOCAL dataOff:DWORD
    LOCAL imgW:DWORD
    LOCAL imgH:DWORD
    LOCAL rowBytes:DWORD
    LOCAL rowStride:DWORD
    LOCAL colourTotal:DWORD

    mov    esi, pBuf

    ; --- 1. signature 'B','M' ------------------------------------------------
    cmp    fileSize, 2
    jb     p_not_bmp               ; shorter than the signature itself
    cmp    BYTE PTR [esi], 'B'
    jne    p_not_bmp
    cmp    BYTE PTR [esi+1], 'M'
    jne    p_not_bmp

    ; --- 2. the 54-byte header must be present --------------------------------
    cmp    fileSize, BMP_HEADER_SIZE
    jb     p_bad_size              ; looks like a BMP but is cut short

    ; --- 3. pixel data offset -------------------------------------------------
    INVOKE Util_ReadLE32, esi, 10
    mov    dataOff, eax
    cmp    eax, BMP_HEADER_SIZE
    jb     p_bad_size              ; pixel data cannot start inside the header

    ; --- 4. info-header size: need the 40-byte BITMAPINFOHEADER or larger ----
    INVOKE Util_ReadLE32, esi, 14
    cmp    eax, 40
    jb     p_bad_size              ; old 12-byte OS/2 header: unsupported

    ; --- 5. bit depth must be 24 ----------------------------------------------
    INVOKE Util_ReadLE16, esi, 28
    cmp    eax, 24
    jne    p_not_24bit

    ; --- 6. no compression ----------------------------------------------------
    INVOKE Util_ReadLE32, esi, 30
    test   eax, eax
    jnz    p_compressed

    ; --- 7. dimensions ----------------------------------------------------------
    INVOKE Util_ReadLE32, esi, 18
    mov    imgW, eax
    INVOKE Util_ReadLE32, esi, 22
    mov    imgH, eax

    cmp    imgW, 0
    jle    p_bad_size              ; signed compare: width must be > 0

    cmp    imgH, 0
    jg     p_h_ok                  ; positive height: bottom-up BMP
    je     p_bad_size              ; height 0 is invalid
    neg    imgH                    ; negative height: top-down BMP, use |h|
    cmp    imgH, 0
    jle    p_bad_size              ; catches the special value 80000000h
p_h_ok:

    ; --- 8. row sizes and total pixel-data size (guard against overflow) ------
    mov    eax, imgW
    mov    ecx, 3
    mul    ecx                     ; EDX:EAX = width * 3
    jc     p_bad_size              ; CF = 1 -> result did not fit in 32 bits
    mov    rowBytes, eax           ; colour bytes per row

    add    eax, 3
    jc     p_bad_size
    and    eax, 0FFFFFFFCh         ; round up to a multiple of 4
    mov    rowStride, eax          ; bytes per row including padding

    mul    imgH                    ; EDX:EAX = rowStride * height
    jc     p_bad_size
    add    eax, dataOff            ; = file offset where pixel data ends
    jc     p_bad_size
    cmp    eax, fileSize
    ja     p_bad_size              ; pixel data runs past the end of the file

    mov    eax, rowBytes
    mul    imgH                    ; fits: rowBytes <= rowStride
    mov    colourTotal, eax        ; usable colour bytes = width*height*3

    ; --- 9. everything is valid: fill the BMPINFO -----------------------------
    mov    edi, pInfo
    mov    eax, pBuf
    mov    [edi].BMPINFO.biBuffer, eax
    mov    eax, fileSize
    mov    [edi].BMPINFO.biFileSize, eax
    mov    eax, dataOff
    mov    [edi].BMPINFO.biDataOffset, eax
    mov    eax, imgW
    mov    [edi].BMPINFO.biWidth, eax
    mov    eax, imgH
    mov    [edi].BMPINFO.biHeight, eax
    mov    [edi].BMPINFO.biBitCount, 24
    mov    eax, rowBytes
    mov    [edi].BMPINFO.biRowBytes, eax
    mov    eax, rowStride
    mov    [edi].BMPINFO.biRowStride, eax
    mov    eax, colourTotal
    mov    [edi].BMPINFO.biColourBytes, eax

    mov    eax, ERR_OK
    ret

p_not_bmp:
    mov    eax, ERR_NOT_BMP
    ret
p_bad_size:
    mov    eax, ERR_BAD_SIZE
    ret
p_not_24bit:
    mov    eax, ERR_NOT_24BIT
    ret
p_compressed:
    mov    eax, ERR_COMPRESSED
    ret
Bmp_Parse ENDP

; ----------------------------------------------------------------------------
; Bmp_Load : read a BMP file into a slot, then validate it with Bmp_Parse
;   In : pPath = zero-terminated file path
;        slot  = SLOT_MAIN or SLOT_SECOND
;   Out: EAX   = ERR_OK or ERR_BAD_SLOT, ERR_FILE_OPEN, ERR_FILE_READ,
;                ERR_TOO_BIG, or any error from Bmp_Parse.
;        On any error the slot is left EMPTY (biBuffer = 0).
; Irvine32 procedures used (all take their arguments in registers):
;   OpenInputFile : EDX = path        -> EAX = handle
;   ReadFromFile  : EAX = handle, EDX = buffer, ECX = max bytes
;                   -> EAX = bytes read, CF = 1 on error
;   CloseFile     : EAX = handle
; ----------------------------------------------------------------------------
Bmp_Load PROC,
    pPath:PTR BYTE, slot:DWORD

    LOCAL hFile:DWORD
    LOCAL bytesRead:DWORD
    LOCAL result:DWORD
    LOCAL pBuf:DWORD
    LOCAL pInfo:DWORD

    ; --- 1. choose the buffer and info block for this slot --------------------
    cmp    slot, SLOT_MAIN
    je     l_slot0
    cmp    slot, SLOT_SECOND
    je     l_slot1
    mov    eax, ERR_BAD_SLOT
    ret
l_slot0:
    mov    pBuf, OFFSET bmpBuf0
    mov    pInfo, OFFSET img0
    jmp    l_slot_done
l_slot1:
    mov    pBuf, OFFSET bmpBuf1
    mov    pInfo, OFFSET img1
l_slot_done:

    ; --- 2. empty the slot first, so an error never leaves a stale image ------
    INVOKE Util_MemZero, pInfo, SIZEOF BMPINFO
    mov    result, ERR_OK
    mov    bytesRead, 0

    ; --- 3. open the file -------------------------------------------------------
    mov    edx, pPath
    call   OpenInputFile
    cmp    eax, INVALID_HANDLE_VALUE
    jne    l_opened
    mov    eax, ERR_FILE_OPEN      ; nothing to close
    ret
l_opened:
    mov    hFile, eax

    ; --- 4. read up to MAX_BMP_SIZE+1 bytes; one extra byte reveals "too big" --
    mov    eax, hFile
    mov    edx, pBuf
    mov    ecx, MAX_BMP_SIZE + 1
    call   ReadFromFile
    jc     l_read_failed           ; CF = 1: the read itself failed
    mov    bytesRead, eax
    cmp    eax, MAX_BMP_SIZE
    ja     l_too_big
    jmp    l_close

l_read_failed:
    mov    result, ERR_FILE_READ
    jmp    l_close
l_too_big:
    mov    result, ERR_TOO_BIG

    ; --- 5. always close the file -----------------------------------------------
l_close:
    mov    eax, hFile
    call   CloseFile

    cmp    result, ERR_OK
    jne    l_done                  ; read problem: report it, slot stays empty

    ; --- 6. validate the bytes and fill the BMPINFO ------------------------------
    INVOKE Bmp_Parse, pBuf, bytesRead, pInfo
    mov    result, eax             ; Parse leaves the BMPINFO empty on error

l_done:
    mov    eax, result
    ret
Bmp_Load ENDP

; ----------------------------------------------------------------------------
; Bmp_Check : make sure a slot number is valid AND holds a loaded image
;   In : slot   = SLOT_MAIN or SLOT_SECOND
;        ppInfo = address of a DWORD that receives the BMPINFO pointer
;   Out: EAX    = ERR_OK, ERR_BAD_SLOT or ERR_NOT_LOADED
; Every operation starts with this call, so the checks live in ONE place.
; ----------------------------------------------------------------------------
Bmp_Check PROC,
    slot:DWORD, ppInfo:PTR DWORD

    INVOKE Bmp_GetInfo, slot
    test   eax, eax
    jz     c_bad_slot
    mov    edx, ppInfo
    mov    [edx], eax              ; hand the BMPINFO pointer to the caller
    cmp    [eax].BMPINFO.biBuffer, 0
    je     c_not_loaded
    xor    eax, eax                ; ERR_OK
    ret
c_bad_slot:
    mov    eax, ERR_BAD_SLOT
    ret
c_not_loaded:
    mov    eax, ERR_NOT_LOADED
    ret
Bmp_Check ENDP

; ----------------------------------------------------------------------------
; Bmp_Save : write the image held in a slot to a new BMP file
;   In : pPath = zero-terminated output path, slot = SLOT_MAIN / SLOT_SECOND
;   Out: EAX   = ERR_OK, ERR_BAD_SLOT, ERR_NOT_LOADED or ERR_FILE_WRITE
; Irvine32 procedures used (registers):
;   CreateOutputFile : EDX = path      -> EAX = handle (creates / overwrites)
;   WriteToFile      : EAX = handle, EDX = buffer, ECX = byte count
;                      -> EAX = bytes written (fewer than ECX means an error)
;   CloseFile        : EAX = handle
; ----------------------------------------------------------------------------
Bmp_Save PROC USES ebx,
    pPath:PTR BYTE, slot:DWORD

    LOCAL pInfo:DWORD
    LOCAL hFile:DWORD
    LOCAL written:DWORD

    INVOKE Bmp_Check, slot, ADDR pInfo
    test   eax, eax
    jnz    s_done                  ; slot invalid or empty: return that error

    mov    edx, pPath
    call   CreateOutputFile
    cmp    eax, INVALID_HANDLE_VALUE
    jne    s_created
    mov    eax, ERR_FILE_WRITE
    jmp    s_done
s_created:
    mov    hFile, eax

    mov    ebx, pInfo
    mov    eax, hFile
    mov    edx, [ebx].BMPINFO.biBuffer
    mov    ecx, [ebx].BMPINFO.biFileSize
    call   WriteToFile
    mov    written, eax

    mov    eax, hFile
    call   CloseFile                ; always close, even after a short write

    mov    ebx, pInfo               ; reload: do not trust EBX after the calls
    mov    eax, written
    cmp    eax, [ebx].BMPINFO.biFileSize
    jne    s_short
    xor    eax, eax                 ; ERR_OK
    jmp    s_done
s_short:
    mov    eax, ERR_FILE_WRITE
s_done:
    ret
Bmp_Save ENDP

END
