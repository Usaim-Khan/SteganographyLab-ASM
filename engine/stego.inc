; ============================================================================
; stego.inc  -  ASM Stego Lab : shared definitions for every engine module
; ----------------------------------------------------------------------------
; Include this at the top of EVERY .asm file (engine and CLI).
; Holds: Irvine32 include, error codes, limits, structures and the prototypes
;        of every exported procedure.
; Rules: * engine procedures NEVER print; they return an error code in EAX
;          (0 = success) and fill result structures.
;        * every procedure is STDCALL (arguments pushed right to left, the
;          callee removes them).  C++ sees them as _Name@<arg bytes>.
; Keep gui/stego_api.h in sync with this file.
; ============================================================================
IFNDEF STEGO_INC
STEGO_INC EQU 1

INCLUDE Irvine32.inc
OPTION CASEMAP:NONE            ; keep exported names exactly as written

; ---------------------------- Error codes -----------------------------------
ERR_OK            EQU 0        ; success
ERR_FILE_OPEN     EQU 1        ; could not open the file
ERR_NOT_BMP       EQU 2        ; missing "BM" signature (or file too short)
ERR_NOT_24BIT     EQU 3        ; bit depth is not 24
ERR_COMPRESSED    EQU 4        ; BMP uses compression
ERR_BAD_SIZE      EQU 5        ; bad dimensions / truncated / inconsistent size
ERR_TOO_BIG       EQU 6        ; file larger than our buffer
ERR_MSG_TOO_BIG   EQU 7        ; message exceeds the image capacity
ERR_NO_SIG        EQU 8        ; no hidden signature found
ERR_BAD_LENGTH    EQU 9        ; hidden length field is impossible
ERR_CRC_BAD       EQU 10       ; CRC mismatch  -> CORRUPTED
ERR_FILE_WRITE    EQU 11       ; could not write the file
ERR_FILE_READ     EQU 12       ; ReadFromFile failed
ERR_BAD_SLOT      EQU 13       ; image slot number is not 0 or 1
ERR_NOT_LOADED    EQU 14       ; no image loaded in that slot
ERR_EMPTY_MSG     EQU 15       ; message length is 0
ERR_BUF_SMALL     EQU 16       ; caller's output buffer is too small
ERR_SIZE_MISMATCH EQU 17       ; Compare: images differ in width or height
ERR_LOG_EMPTY     EQU 18       ; log file is empty or missing
ERR_LOG_FULL      EQU 19       ; log file reached its size limit
ERR_SAME_FILE     EQU 20       ; output file would overwrite the cover image
ERR_COUNT         EQU 21       ; number of codes (used by Stego_ErrorText)

; ---------------------------- Limits and layout -----------------------------
MAX_BMP_SIZE    EQU 8388608    ; largest BMP we load: 8 MB
BMP_HEADER_SIZE EQU 54         ; 14-byte file header + 40-byte info header
SLOT_MAIN       EQU 0          ; slot 0: main / original image
SLOT_SECOND     EQU 1          ; slot 1: second image (used by Compare)
PIX_INVALID     EQU 0FFFFFFFFh ; "no such colour byte" marker
PKT_OVERHEAD    EQU 12         ; signature(4) + length(4) + CRC-32(4)
MSG_MAX         EQU 4096       ; longest message the front ends accept
LOG_BUF_SIZE    EQU 65536      ; the log file is limited to 64 KB
LOG_LINE_MAX    EQU 1100       ; longest single log line

; ---------------------------- Structures ------------------------------------
; Filled by Bmp_Parse. All later modules read image facts from here.
BMPINFO STRUCT
    biBuffer      DWORD ?      ; pointer to the loaded file bytes (0 = empty)
    biFileSize    DWORD ?      ; bytes loaded
    biDataOffset  DWORD ?      ; file offset where pixel data starts
    biWidth       DWORD ?      ; pixels per row
    biHeight      DWORD ?      ; rows (absolute value)
    biBitCount    DWORD ?      ; always 24 once validated
    biRowBytes    DWORD ?      ; width*3  : colour bytes in one row
    biRowStride   DWORD ?      ; rowBytes rounded up to a multiple of 4
    biColourBytes DWORD ?      ; width*height*3 : all usable colour bytes
BMPINFO ENDS

; Result of Pkt_Verify / Op_Verify
VERIFYINFO STRUCT
    viMsgLen      DWORD ?      ; hidden message length in bytes
    viStoredCrc   DWORD ?      ; CRC-32 stored inside the image
    viCalcCrc     DWORD ?      ; CRC-32 recomputed from the extracted message
VERIFYINFO ENDS

; Result of An_Analyze / Op_Analyze
ANALYSISINFO STRUCT
    aiWidth       DWORD ?
    aiHeight      DWORD ?
    aiBitCount    DWORD ?
    aiFileSize    DWORD ?
    aiDataOffset  DWORD ?
    aiRowStride   DWORD ?
    aiPixelCount  DWORD ?      ; width * height
    aiColourBytes DWORD ?      ; width * height * 3
    aiCapacity    DWORD ?      ; largest message (bytes) this image can hold
    aiAvgB        DWORD ?      ; mean blue  value 0..255
    aiAvgG        DWORD ?      ; mean green value 0..255
    aiAvgR        DWORD ?      ; mean red   value 0..255
    aiLsbOnes     DWORD ?      ; colour bytes whose lowest bit is 1
    aiHasMessage  DWORD ?      ; 1 if a valid hidden header was found
    aiMsgLen      DWORD ?      ; length from that header (else 0)
ANALYSISINFO ENDS

; Result of An_Compare / Op_Compare.  10 DWORDs (40 bytes) then two REAL8, so
; the doubles start at offset 40 (a multiple of 8) in both MASM and C++.
COMPAREINFO STRUCT
    ciWidth        DWORD ?
    ciHeight       DWORD ?
    ciColourBytes  DWORD ?
    ciChangedBytes DWORD ?     ; colour bytes that differ
    ciChangedBits  DWORD ?     ; individual bits that differ
    ciMaxDiff      DWORD ?     ; largest |a-b| seen
    ciSumSqLo      DWORD ?     ; sum of (a-b)^2 as a 64-bit number:
    ciSumSqHi      DWORD ?     ;   low half first (little-endian QWORD)
    ciIdentical    DWORD ?     ; 1 if no colour byte differs
    ciReserved     DWORD ?
    ciMse          REAL8 ?     ; mean squared error
    ciPsnr         REAL8 ?     ; 10*log10(255^2 / MSE) in dB (0 if identical)
COMPAREINFO ENDS

; ---------------------------- Prototypes ------------------------------------
; --- util.asm : small reusable helpers ---
Util_ReadLE16   PROTO, pBuf:PTR BYTE, offs:DWORD                 ; EAX = word
Util_ReadLE32   PROTO, pBuf:PTR BYTE, offs:DWORD                 ; EAX = dword
Util_WriteLE32  PROTO, pBuf:PTR BYTE, offs:DWORD, value:DWORD
Util_MemCopy    PROTO, pDest:PTR BYTE, pSrc:PTR BYTE, count:DWORD
Util_MemZero    PROTO, pDest:PTR BYTE, count:DWORD
Util_TrimPath   PROTO, pStr:PTR BYTE                             ; edits in place
Util_StrCat     PROTO, pDest:PTR BYTE, pSrc:PTR BYTE             ; append text
Util_UIntToStr  PROTO, pDest:PTR BYTE, value:DWORD               ; EAX = length
Util_Put2       PROTO, pDest:PTR BYTE, value:DWORD               ; 2 digits, no 0

; --- bmp.asm : load, parse, validate, save ---
Bmp_Parse       PROTO, pBuf:PTR BYTE, fileSize:DWORD, pInfo:PTR BMPINFO
Bmp_Load        PROTO, pPath:PTR BYTE, slot:DWORD                ; EAX = error
Bmp_Save        PROTO, pPath:PTR BYTE, slot:DWORD                ; EAX = error
Bmp_GetInfo     PROTO, slot:DWORD                                ; EAX = PTR BMPINFO or 0
Bmp_Check       PROTO, slot:DWORD, ppInfo:PTR DWORD              ; EAX = error

; --- pixel.asm : colour-byte addressing and LSB bit access ---
Pix_Index       PROTO, pInfo:PTR BMPINFO, n:DWORD                ; EAX = file offset
Pix_EmbedByte   PROTO, pInfo:PTR BMPINFO, byteIdx:DWORD, value:DWORD   ; EAX = error
Pix_ExtractByte PROTO, pInfo:PTR BMPINFO, byteIdx:DWORD          ; EAX = byte or PIX_INVALID

; --- crc32.asm : table-driven CRC-32 ---
Crc_Init        PROTO                                            ; builds the table once
Crc_UpdateByte  PROTO, crc:DWORD, b:DWORD                        ; EAX = new running crc
Crc_Compute     PROTO, pBuf:PTR BYTE, len:DWORD                  ; EAX = final CRC-32

; --- packet.asm : hidden packet (signature, length, message, CRC-32) ---
Pkt_Capacity    PROTO, pInfo:PTR BMPINFO                         ; EAX = max message bytes
Pkt_ReadHeader  PROTO, pInfo:PTR BMPINFO, pLen:PTR DWORD         ; EAX = error
Pkt_Hide        PROTO, slot:DWORD, pMsg:PTR BYTE, msgLen:DWORD
Pkt_Extract     PROTO, slot:DWORD, pOut:PTR BYTE, maxOut:DWORD, pOutLen:PTR DWORD
Pkt_Verify      PROTO, slot:DWORD, pVI:PTR VERIFYINFO

; --- analysis.asm : single-image analysis, two-image comparison (x87) ---
An_Analyze      PROTO, slot:DWORD, pAI:PTR ANALYSISINFO
An_Compare      PROTO, slotA:DWORD, slotB:DWORD, pCI:PTR COMPAREINFO

; --- log.asm : timestamped log file ---
Log_SetFile     PROTO, pName:PTR BYTE                            ; NULL = default name
Log_Timestamp   PROTO, pDest:PTR BYTE                            ; "YYYY-MM-DD HH:MM:SS"
Log_Write       PROTO, pText:PTR BYTE
Log_Read        PROTO, pOut:PTR BYTE, maxOut:DWORD, pOutLen:PTR DWORD
Log_Clear       PROTO
Log_Backup      PROTO, pNameInOut:PTR BYTE                       ; empty name = auto name

; --- ops.asm : the six user operations; each one also writes a log line ---
Op_Hide         PROTO, pCover:PTR BYTE, pOut:PTR BYTE, pMsg:PTR BYTE, msgLen:DWORD
Op_Extract      PROTO, pStego:PTR BYTE, pOut:PTR BYTE, maxOut:DWORD, pOutLen:PTR DWORD
Op_Verify       PROTO, pStego:PTR BYTE, pVI:PTR VERIFYINFO
Op_Analyze      PROTO, pImage:PTR BYTE, pAI:PTR ANALYSISINFO
Op_Compare      PROTO, pOrig:PTR BYTE, pEnc:PTR BYTE, pCI:PTR COMPAREINFO

; --- errors.asm : text for error codes (same wording in CLI and GUI) ---
Stego_ErrorText PROTO, errCode:DWORD                             ; EAX = PTR to string

; --- smoke.asm : Step 0 test, kept only for reference ---
Stego_SmokeTest PROTO, pPath:PTR BYTE

ENDIF
