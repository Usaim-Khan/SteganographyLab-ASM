; ============================================================================
; ops.asm  -  the user operations (application layer)
; ----------------------------------------------------------------------------
; Each operation = load file(s) -> engine work -> save/return results -> write
; one line to the log. The CLI and the GUI call ONLY these, so both front ends
; behave identically and every action is logged exactly once.
; A failed log write never makes an operation fail.
; ============================================================================
INCLUDE stego.inc

.data
sHide      BYTE "HIDE",0
sExtract   BYTE "EXTRACT",0
sVerify    BYTE "VERIFY",0
sAnalyze   BYTE "ANALYZE",0
sCompare   BYTE "COMPARE",0
txtOk      BYTE " OK",0
txtFailed  BYTE " FAILED: ",0
txtSep     BYTE " | ",0
txtArrow   BYTE " -> ",0

.data?
opLine     BYTE LOG_LINE_MAX DUP(?)

.code

; ----------------------------------------------------------------------------
; Ops_Log (internal) : write "<ACTION> OK | file1 -> file2" or
;                      "<ACTION> FAILED: <reason> | file1 -> file2"
;   pFile1 / pFile2 may be NULL when not used.
; ----------------------------------------------------------------------------
Ops_Log PROC USES eax,
    pAction:PTR BYTE, pFile1:PTR BYTE, pFile2:PTR BYTE, errCode:DWORD

    mov    BYTE PTR opLine, 0
    INVOKE Util_StrCat, ADDR opLine, pAction
    cmp    errCode, ERR_OK
    jne    ol_failed
    INVOKE Util_StrCat, ADDR opLine, ADDR txtOk
    jmp    ol_files
ol_failed:
    INVOKE Util_StrCat, ADDR opLine, ADDR txtFailed
    INVOKE Stego_ErrorText, errCode          ; EAX = reason text
    INVOKE Util_StrCat, ADDR opLine, eax
ol_files:
    cmp    pFile1, 0
    je     ol_write
    INVOKE Util_StrCat, ADDR opLine, ADDR txtSep
    INVOKE Util_StrCat, ADDR opLine, pFile1
    cmp    pFile2, 0
    je     ol_write
    INVOKE Util_StrCat, ADDR opLine, ADDR txtArrow
    INVOKE Util_StrCat, ADDR opLine, pFile2
ol_write:
    INVOKE Log_Write, ADDR opLine            ; result ignored on purpose
    ret
Ops_Log ENDP

; ----------------------------------------------------------------------------
; Op_Hide : hide a message in a cover image and save the encoded image
;   In : pCover = cover BMP path, pOut = encoded BMP path (must differ),
;        pMsg / msgLen = the message
;   Out: EAX = ERR_OK or any load / hide / save error, or ERR_SAME_FILE
; ----------------------------------------------------------------------------
Op_Hide PROC,
    pCover:PTR BYTE, pOut:PTR BYTE, pMsg:PTR BYTE, msgLen:DWORD

    LOCAL result:DWORD

    INVOKE Str_compare, pCover, pOut         ; ZF = 1 when the two paths are equal
    jne    oh_diff
    mov    result, ERR_SAME_FILE             ; refuse to overwrite the cover image
    jmp    oh_log
oh_diff:
    INVOKE Bmp_Load, pCover, SLOT_MAIN
    test   eax, eax
    jnz    oh_set
    INVOKE Pkt_Hide, SLOT_MAIN, pMsg, msgLen
    test   eax, eax
    jnz    oh_set
    INVOKE Bmp_Save, pOut, SLOT_MAIN
oh_set:
    mov    result, eax
oh_log:
    INVOKE Ops_Log, ADDR sHide, pCover, pOut, result
    mov    eax, result
    ret
Op_Hide ENDP

; ----------------------------------------------------------------------------
; Op_Extract : load an image and read the hidden message out of it
;   In : pStego = image path, pOut / maxOut = buffer for the message,
;        pOutLen = receives its length
;   Out: EAX = ERR_OK, ERR_NO_SIG, ERR_BAD_LENGTH, ERR_BUF_SMALL, load errors
; ----------------------------------------------------------------------------
Op_Extract PROC,
    pStego:PTR BYTE, pOut:PTR BYTE, maxOut:DWORD, pOutLen:PTR DWORD

    LOCAL result:DWORD

    INVOKE Bmp_Load, pStego, SLOT_MAIN
    test   eax, eax
    jnz    ox_set
    INVOKE Pkt_Extract, SLOT_MAIN, pOut, maxOut, pOutLen
ox_set:
    mov    result, eax
    INVOKE Ops_Log, ADDR sExtract, pStego, 0, result
    mov    eax, result
    ret
Op_Extract ENDP

; ----------------------------------------------------------------------------
; Op_Verify : load an image and check the hidden message against its CRC-32
;   Out: EAX = ERR_OK (VALID), ERR_CRC_BAD (CORRUPTED, pVI still filled in),
;              ERR_NO_SIG, ERR_BAD_LENGTH, load errors
; ----------------------------------------------------------------------------
Op_Verify PROC,
    pStego:PTR BYTE, pVI:PTR VERIFYINFO

    LOCAL result:DWORD

    INVOKE Bmp_Load, pStego, SLOT_MAIN
    test   eax, eax
    jnz    ov_set
    INVOKE Pkt_Verify, SLOT_MAIN, pVI
ov_set:
    mov    result, eax
    INVOKE Ops_Log, ADDR sVerify, pStego, 0, result
    mov    eax, result
    ret
Op_Verify ENDP

; ----------------------------------------------------------------------------
; Op_Analyze : load an image and fill an ANALYSISINFO
; ----------------------------------------------------------------------------
Op_Analyze PROC,
    pImage:PTR BYTE, pAI:PTR ANALYSISINFO

    LOCAL result:DWORD

    INVOKE Bmp_Load, pImage, SLOT_MAIN
    test   eax, eax
    jnz    oa_set
    INVOKE An_Analyze, SLOT_MAIN, pAI
oa_set:
    mov    result, eax
    INVOKE Ops_Log, ADDR sAnalyze, pImage, 0, result
    mov    eax, result
    ret
Op_Analyze ENDP

; ----------------------------------------------------------------------------
; Op_Compare : load an original (slot 0) and an encoded image (slot 1) and
;              compare them: changed bytes/bits, MSE, PSNR
; ----------------------------------------------------------------------------
Op_Compare PROC,
    pOrig:PTR BYTE, pEnc:PTR BYTE, pCI:PTR COMPAREINFO

    LOCAL result:DWORD

    INVOKE Bmp_Load, pOrig, SLOT_MAIN
    test   eax, eax
    jnz    oc_set
    INVOKE Bmp_Load, pEnc, SLOT_SECOND
    test   eax, eax
    jnz    oc_set
    INVOKE An_Compare, SLOT_MAIN, SLOT_SECOND, pCI
oc_set:
    mov    result, eax
    INVOKE Ops_Log, ADDR sCompare, pOrig, pEnc, result
    mov    eax, result
    ret
Op_Compare ENDP

END
