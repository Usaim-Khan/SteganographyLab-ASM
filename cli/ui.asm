; ============================================================================
; ui.asm  -  console screens for the six operations
; ----------------------------------------------------------------------------
; The CLI only asks questions and prints answers. All real work is done by the
; Op_* procedures of the shared engine (which also write the log).
; ============================================================================
INCLUDE stego.inc

RunSelfTest PROTO, pFolder:PTR BYTE     ; defined in selftest.asm

.data
; ---- prompts ---------------------------------------------------------------
pCover     BYTE "Cover image (24-bit BMP): ",0
pOutImg    BYTE "Save encoded image as (a NEW file name): ",0
pMsg       BYTE "Message to hide: ",0
pStego     BYTE "Image to read (BMP): ",0
pOrig      BYTE "Original image (BMP): ",0
pEnc       BYTE "Encoded image (BMP): ",0
pFolder    BYTE "Tests folder (just Enter = ",0
pFolderEnd BYTE "): ",0
; ---------------------------------------------------------------------------
; DEFAULT TESTS FOLDER (menu option 7, when you just press Enter).
; Change the text between the quotes to the folder that holds the test .bmp
; files. Write the path exactly as Windows shows it (single backslashes).
; Keep it under 200 characters.
;   relative to the project folder (works when the working folder is StegoCLI):
;       defFolder  BYTE "..\tests",0
; ---------------------------------------------------------------------------
defFolder  BYTE "..\tests",0
reportMenu BYTE 0Dh,0Ah,"--- Handle Report (log file) ---",0Dh,0Ah
           BYTE " 1. View the log",0Dh,0Ah
           BYTE " 2. Clear the log",0Dh,0Ah
           BYTE " 3. Back up the log (then start a new one)",0Dh,0Ah
           BYTE " 0. Back to the main menu",0Dh,0Ah
           BYTE "Choice: ",0

; ---- messages --------------------------------------------------------------
errPrefix  BYTE "Error ",0
errColon   BYTE ": ",0
msgHidden  BYTE "Message hidden. The encoded image was saved.",0Dh,0Ah,0
msgHeader  BYTE "Hidden message:",0Dh,0Ah,0
msgValid   BYTE "Result: VALID  (stored and calculated CRC-32 match)",0Dh,0Ah,0
msgCorrupt BYTE "Result: CORRUPTED  (the CRC-32 values differ)",0Dh,0Ah,0
msgHasMsg  BYTE "  Hidden message present   : yes",0Dh,0Ah,0
msgNoMsg   BYTE "  Hidden message present   : no",0Dh,0Ah,0
msgIdent   BYTE "  The images are identical (MSE = 0, PSNR is infinite).",0Dh,0Ah,0
msgLogEmpty BYTE "(the log is empty)",0Dh,0Ah,0
msgCleared BYTE "The log was cleared.",0Dh,0Ah,0
msgBackup  BYTE "Backup saved as: ",0
msgPSNRdB  BYTE " dB",0Dh,0Ah,0

; ---- labels ----------------------------------------------------------------
lMsgLen    BYTE "  Message length (bytes)   : ",0
lStored    BYTE "  Stored CRC-32            : ",0
lCalc      BYTE "  Calculated CRC-32        : ",0
lWidth     BYTE "  Width (pixels)           : ",0
lHeight    BYTE "  Height (pixels)          : ",0
lBits      BYTE "  Bits per pixel           : ",0
lFileSize  BYTE "  File size (bytes)        : ",0
lDataOff   BYTE "  Pixel data offset        : ",0
lStride    BYTE "  Row stride (bytes)       : ",0
lPixels    BYTE "  Pixel count              : ",0
lColour    BYTE "  Colour bytes             : ",0
lCapacity  BYTE "  Capacity (message bytes) : ",0
lAvgB      BYTE "  Average blue  (0-255)    : ",0
lAvgG      BYTE "  Average green (0-255)    : ",0
lAvgR      BYTE "  Average red   (0-255)    : ",0
lOnes      BYTE "  Bytes with lowest bit = 1: ",0
lOnesPct   BYTE "  ... as a percentage      : ",0
lAMsgLen   BYTE "  Hidden message length    : ",0
lChBytes   BYTE "  Changed colour bytes     : ",0
lChBits    BYTE "  Changed bits             : ",0
lMaxDiff   BYTE "  Largest difference       : ",0
lMse       BYTE "  MSE                      : ",0
lPsnr      BYTE "  PSNR                     : ",0

const10000 REAL8 10000.0

.data?
pathA      BYTE 260 DUP(?)
pathB      BYTE 260 DUP(?)
nameBuf    BYTE 260 DUP(?)
folderBuf  BYTE 260 DUP(?)
msgBuf     BYTE MSG_MAX + 1 DUP(?)
outBuf     BYTE MSG_MAX + 1 DUP(?)
logView    BYTE LOG_BUF_SIZE + 1 DUP(?)
viU        VERIFYINFO <>
aiU        ANALYSISINFO <>
ciU        COMPAREINFO <>

.code

; ----------------------------------------------------------------------------
; ShowField : print "<label><number>" and a new line (keeps all registers)
; ShowFieldHex : same, but the number is printed as 8 hexadecimal digits
; ----------------------------------------------------------------------------
ShowField PROC USES eax ebx ecx edx esi edi,
    pLabel:PTR BYTE, value:DWORD

    mov    edx, pLabel
    call   WriteString
    mov    eax, value
    call   WriteDec                  ; prints EAX as an unsigned decimal number
    call   Crlf
    ret
ShowField ENDP

ShowFieldHex PROC USES eax ebx ecx edx esi edi,
    pLabel:PTR BYTE, value:DWORD

    mov    edx, pLabel
    call   WriteString
    mov    eax, value
    call   WriteHex                  ; prints EAX as 8 hexadecimal digits
    call   Crlf
    ret
ShowFieldHex ENDP

; ----------------------------------------------------------------------------
; ShowError : print "Error <code>: <text>"; the text comes from the engine
;             (Stego_ErrorText) so the GUI uses exactly the same wording
; ----------------------------------------------------------------------------
ShowError PROC USES eax edx,
    errCode:DWORD

    mov    edx, OFFSET errPrefix
    call   WriteString
    mov    eax, errCode
    call   WriteDec
    mov    edx, OFFSET errColon
    call   WriteString
    INVOKE Stego_ErrorText, errCode
    mov    edx, eax                  ; EAX = pointer to the message text
    call   WriteString
    call   Crlf
    ret
ShowError ENDP

; ----------------------------------------------------------------------------
; PrintFixed4 : print a REAL8 with 4 decimals, e.g. 48.1234  (value >= 0)
;   Method: multiply by 10000, round to an integer with the FPU, then split
;   into integer part and 4 fraction digits with DIV.
; ----------------------------------------------------------------------------
PrintFixed4 PROC USES eax ebx ecx edx,
    pReal8:PTR REAL8

    LOCAL scaled:DWORD
    LOCAL rem:DWORD
    LOCAL divisor:DWORD

    mov    eax, pReal8
    fld    QWORD PTR [eax]           ; ST0 = value
    fmul   const10000                ; ST0 = value * 10000
    fistp  scaled                    ; round to nearest integer, pop the FPU stack
    mov    eax, scaled
    xor    edx, edx
    mov    ecx, 10000
    div    ecx                       ; EAX = integer part, EDX = 4 fraction digits
    mov    rem, edx
    call   WriteDec                  ; integer part
    mov    al, '.'
    call   WriteChar
    mov    divisor, 1000             ; print the fraction digit by digit
pf_loop:
    mov    eax, rem
    xor    edx, edx
    div    divisor                   ; EAX = next digit, EDX = what is left
    mov    rem, edx
    call   WriteDec
    mov    eax, divisor
    xor    edx, edx
    mov    ecx, 10
    div    ecx
    mov    divisor, eax              ; 1000 -> 100 -> 10 -> 1 -> 0
    test   eax, eax
    jnz    pf_loop
    ret
PrintFixed4 ENDP

; ----------------------------------------------------------------------------
; ReadPath : show a prompt, read a line, remove quotes and spaces around it
; ----------------------------------------------------------------------------
ReadPath PROC USES eax ecx edx,
    pPrompt:PTR BYTE, pBuf:PTR BYTE

    mov    edx, pPrompt
    call   WriteString
    mov    edx, pBuf
    mov    ecx, 259                  ; the buffers hold 260 bytes
    call   ReadString
    INVOKE Util_TrimPath, pBuf       ; accepts a pasted "quoted" path
    ret
ReadPath ENDP

; ============================== Hide Message ================================
DoHide PROC USES ecx edx
    LOCAL msgLen:DWORD

    INVOKE ReadPath, ADDR pCover, ADDR pathA
    INVOKE ReadPath, ADDR pOutImg, ADDR pathB
    mov    edx, OFFSET pMsg
    call   WriteString
    mov    edx, OFFSET msgBuf
    mov    ecx, MSG_MAX
    call   ReadString                ; EAX = number of characters typed
    mov    msgLen, eax

    INVOKE Op_Hide, ADDR pathA, ADDR pathB, ADDR msgBuf, msgLen
    cmp    eax, ERR_OK
    jne    dh_fail
    mov    edx, OFFSET msgHidden
    call   WriteString
    INVOKE ShowField, ADDR lMsgLen, msgLen
    ret
dh_fail:
    INVOKE ShowError, eax
    ret
DoHide ENDP

; ============================== Extract Message =============================
DoExtract PROC USES edx
    LOCAL outLen:DWORD

    INVOKE ReadPath, ADDR pStego, ADDR pathA
    INVOKE Op_Extract, ADDR pathA, ADDR outBuf, MSG_MAX + 1, ADDR outLen
    cmp    eax, ERR_OK
    jne    de_fail
    mov    edx, OFFSET msgHeader
    call   WriteString
    mov    edx, OFFSET outBuf
    call   WriteString
    call   Crlf
    INVOKE ShowField, ADDR lMsgLen, outLen
    ret
de_fail:
    INVOKE ShowError, eax
    ret
DoExtract ENDP

; ============================== Verify Integrity ============================
DoVerify PROC USES edx

    INVOKE ReadPath, ADDR pStego, ADDR pathA
    INVOKE Op_Verify, ADDR pathA, ADDR viU
    cmp    eax, ERR_OK
    je     dv_show
    cmp    eax, ERR_CRC_BAD
    je     dv_show                   ; corrupted: the values are still valid to show
    INVOKE ShowError, eax
    ret
dv_show:
    push   eax                       ; remember VALID (0) or CORRUPTED (ERR_CRC_BAD)
    INVOKE ShowField,    ADDR lMsgLen, viU.viMsgLen
    INVOKE ShowFieldHex, ADDR lStored, viU.viStoredCrc
    INVOKE ShowFieldHex, ADDR lCalc,   viU.viCalcCrc
    pop    eax
    cmp    eax, ERR_OK
    jne    dv_bad
    mov    edx, OFFSET msgValid
    call   WriteString
    ret
dv_bad:
    mov    edx, OFFSET msgCorrupt
    call   WriteString
    ret
DoVerify ENDP

; ============================== Analyze Image ===============================
DoAnalyze PROC USES ecx edx
    LOCAL pct:DWORD

    INVOKE ReadPath, ADDR pStego, ADDR pathA
    INVOKE Op_Analyze, ADDR pathA, ADDR aiU
    cmp    eax, ERR_OK
    je     da_show
    INVOKE ShowError, eax
    ret
da_show:
    INVOKE ShowField, ADDR lWidth,    aiU.aiWidth
    INVOKE ShowField, ADDR lHeight,   aiU.aiHeight
    INVOKE ShowField, ADDR lBits,     aiU.aiBitCount
    INVOKE ShowField, ADDR lFileSize, aiU.aiFileSize
    INVOKE ShowField, ADDR lDataOff,  aiU.aiDataOffset
    INVOKE ShowField, ADDR lStride,   aiU.aiRowStride
    INVOKE ShowField, ADDR lPixels,   aiU.aiPixelCount
    INVOKE ShowField, ADDR lColour,   aiU.aiColourBytes
    INVOKE ShowField, ADDR lCapacity, aiU.aiCapacity
    INVOKE ShowField, ADDR lAvgB,     aiU.aiAvgB
    INVOKE ShowField, ADDR lAvgG,     aiU.aiAvgG
    INVOKE ShowField, ADDR lAvgR,     aiU.aiAvgR
    INVOKE ShowField, ADDR lOnes,     aiU.aiLsbOnes
    mov    eax, aiU.aiLsbOnes        ; percentage = ones * 100 / colour bytes
    mov    ecx, 100
    mul    ecx                       ; EDX:EAX = ones * 100 (fits in 32 bits)
    div    aiU.aiColourBytes
    mov    pct, eax
    INVOKE ShowField, ADDR lOnesPct,  pct
    cmp    aiU.aiHasMessage, 0
    je     da_none
    mov    edx, OFFSET msgHasMsg
    call   WriteString
    INVOKE ShowField, ADDR lAMsgLen,  aiU.aiMsgLen
    ret
da_none:
    mov    edx, OFFSET msgNoMsg
    call   WriteString
    ret
DoAnalyze ENDP

; ============================== Compare Images ==============================
DoCompare PROC USES edx

    INVOKE ReadPath, ADDR pOrig, ADDR pathA
    INVOKE ReadPath, ADDR pEnc,  ADDR pathB
    INVOKE Op_Compare, ADDR pathA, ADDR pathB, ADDR ciU
    cmp    eax, ERR_OK
    je     dc_show
    INVOKE ShowError, eax
    ret
dc_show:
    INVOKE ShowField, ADDR lWidth,   ciU.ciWidth
    INVOKE ShowField, ADDR lHeight,  ciU.ciHeight
    INVOKE ShowField, ADDR lChBytes, ciU.ciChangedBytes
    INVOKE ShowField, ADDR lChBits,  ciU.ciChangedBits
    INVOKE ShowField, ADDR lMaxDiff, ciU.ciMaxDiff
    cmp    ciU.ciIdentical, 0
    je     dc_float
    mov    edx, OFFSET msgIdent
    call   WriteString
    ret
dc_float:
    mov    edx, OFFSET lMse
    call   WriteString
    INVOKE PrintFixed4, ADDR ciU.ciMse
    call   Crlf
    mov    edx, OFFSET lPsnr
    call   WriteString
    INVOKE PrintFixed4, ADDR ciU.ciPsnr
    mov    edx, OFFSET msgPSNRdB
    call   WriteString
    ret
DoCompare ENDP

; ============================== Handle Report ===============================
DoReport PROC USES edx
    LOCAL logLen:DWORD

dr_loop:
    mov    edx, OFFSET reportMenu
    call   WriteString
    call   ReadInt                   ; OF = 1 if the input was not a number
    jo     dr_loop
    cmp    eax, 1
    je     dr_view
    cmp    eax, 2
    je     dr_clear
    cmp    eax, 3
    je     dr_backup
    cmp    eax, 0
    je     dr_done
    jmp    dr_loop

dr_view:
    INVOKE Log_Read, ADDR logView, LOG_BUF_SIZE + 1, ADDR logLen
    test   eax, eax
    jnz    dr_err
    cmp    logLen, 0
    jne    dr_text
    mov    edx, OFFSET msgLogEmpty
    call   WriteString
    jmp    dr_loop
dr_text:
    mov    edx, OFFSET logView
    call   WriteString
    jmp    dr_loop

dr_clear:
    INVOKE Log_Clear
    test   eax, eax
    jnz    dr_err
    mov    edx, OFFSET msgCleared
    call   WriteString
    jmp    dr_loop

dr_backup:
    mov    BYTE PTR nameBuf, 0       ; empty name = "make one from the time"
    INVOKE Log_Backup, ADDR nameBuf
    test   eax, eax
    jnz    dr_err
    mov    edx, OFFSET msgBackup
    call   WriteString
    mov    edx, OFFSET nameBuf
    call   WriteString
    call   Crlf
    jmp    dr_loop

dr_err:
    INVOKE ShowError, eax
    jmp    dr_loop
dr_done:
    ret
DoReport ENDP

; ============================== Self-test ===================================
DoSelfTest PROC USES ecx edx

    mov    edx, OFFSET pFolder
    call   WriteString
    mov    edx, OFFSET defFolder            ; show what Enter will use
    call   WriteString
    mov    edx, OFFSET pFolderEnd
    call   WriteString
    mov    edx, OFFSET folderBuf
    mov    ecx, 259
    call   ReadString
    INVOKE Util_TrimPath, ADDR folderBuf
    cmp    folderBuf, 0
    jne    st_run                    ; something was typed
    INVOKE Str_copy, ADDR defFolder, ADDR folderBuf
st_run:
    INVOKE RunSelfTest, ADDR folderBuf
    ret
DoSelfTest ENDP

END