; ============================================================================
; log.asm  -  timestamped log file ("Handle Report")
; ----------------------------------------------------------------------------
; One line per action:   [2026-10-15 14:03:22] HIDE OK | cover.bmp -> out.bmp
; The log lives in the program's working folder (default stego_log.txt).
;
; Irvine32 can create/overwrite, open, read, write and close files, but it has
; no "append" and no "delete". So:
;   * adding a line = read the whole log, add the line, write it all back
;     (the log is limited to 64 KB; Log_Write reports ERR_LOG_FULL beyond that)
;   * "clear" and the "delete the original" part of a backup = re-create the
;     file empty, which starts a new log exactly like deleting it would.
; Windows API used here: GetLocalTime only (Irvine32 has no clock/date call).
; ============================================================================
INCLUDE stego.inc

IFNDEF GetLocalTime                  ; declare it only if Irvine32.inc has not
GetLocalTime PROTO, lpSystemTime:PTR BYTE
ENDIF

; Same layout as the Windows SYSTEMTIME structure (8 WORDs = 16 bytes)
STGTIME STRUCT
    wYear         WORD ?
    wMonth        WORD ?
    wDayOfWeek    WORD ?
    wDay          WORD ?
    wHour         WORD ?
    wMinute       WORD ?
    wSecond       WORD ?
    wMilliseconds WORD ?
STGTIME ENDS

.data
defaultLog BYTE "stego_log.txt",0
logPath    BYTE "stego_log.txt",0      ; current log file name (can be changed)
           BYTE 240 DUP(0)             ; spare room so a longer name fits
bakPrefix  BYTE "stego_log_",0
bakSuffix  BYTE ".txt",0
txtOpen    BYTE "[",0
txtClose   BYTE "] ",0
txtCRLF    BYTE 0Dh,0Ah,0
txtNewLog  BYTE "New log started. Previous log saved as ",0

.data?
logBuf     BYTE LOG_BUF_SIZE DUP(?)   ; whole log file in memory
lineBuf    BYTE LOG_LINE_MAX + 64 DUP(?)
noteBuf    BYTE 512 DUP(?)
tsBuf      BYTE 32 DUP(?)
stTime     STGTIME <>

.code

; ----------------------------------------------------------------------------
; Log_SetFile : choose the log file name (NULL or "" = back to the default)
;   Used by the self-test so it does not touch the user's real log.
; ----------------------------------------------------------------------------
Log_SetFile PROC USES eax,
    pName:PTR BYTE

    mov    eax, pName
    test   eax, eax
    jz     ls_reset
    cmp    BYTE PTR [eax], 0
    je     ls_reset
    INVOKE Str_length, pName
    cmp    eax, 240
    ja     ls_done                   ; name too long: keep the current one
    INVOKE Str_copy, pName, ADDR logPath
    jmp    ls_done
ls_reset:
    INVOKE Str_copy, ADDR defaultLog, ADDR logPath
ls_done:
    ret
Log_SetFile ENDP

; ----------------------------------------------------------------------------
; Log_Timestamp : write the local date and time as "YYYY-MM-DD HH:MM:SS"
;   pDest needs 20 bytes (19 characters + terminating zero).
; ----------------------------------------------------------------------------
Log_Timestamp PROC USES eax edi,
    pDest:PTR BYTE

    INVOKE GetLocalTime, ADDR stTime     ; fills the 8 WORD fields
    mov    edi, pDest

    movzx  eax, stTime.wYear
    INVOKE Util_UIntToStr, edi, eax      ; "2026", returns the length
    add    edi, eax
    mov    BYTE PTR [edi], '-'
    inc    edi
    movzx  eax, stTime.wMonth
    INVOKE Util_Put2, edi, eax
    add    edi, 2
    mov    BYTE PTR [edi], '-'
    inc    edi
    movzx  eax, stTime.wDay
    INVOKE Util_Put2, edi, eax
    add    edi, 2
    mov    BYTE PTR [edi], ' '
    inc    edi
    movzx  eax, stTime.wHour
    INVOKE Util_Put2, edi, eax
    add    edi, 2
    mov    BYTE PTR [edi], ':'
    inc    edi
    movzx  eax, stTime.wMinute
    INVOKE Util_Put2, edi, eax
    add    edi, 2
    mov    BYTE PTR [edi], ':'
    inc    edi
    movzx  eax, stTime.wSecond
    INVOKE Util_Put2, edi, eax
    add    edi, 2
    mov    BYTE PTR [edi], 0
    ret
Log_Timestamp ENDP

; ----------------------------------------------------------------------------
; Log_ReadRaw (internal) : read the log file into logBuf
;   Out: EAX = number of bytes read (0 if the file is missing or empty)
; ----------------------------------------------------------------------------
Log_ReadRaw PROC
    LOCAL hFile:DWORD
    LOCAL got:DWORD

    mov    got, 0
    mov    edx, OFFSET logPath
    call   OpenInputFile
    cmp    eax, INVALID_HANDLE_VALUE
    je     lr_done                   ; no log yet: that is just an empty log
    mov    hFile, eax

    mov    eax, hFile
    mov    edx, OFFSET logBuf
    mov    ecx, LOG_BUF_SIZE
    call   ReadFromFile
    jc     lr_close                  ; read failed: treat as empty
    mov    got, eax
lr_close:
    mov    eax, hFile
    call   CloseFile
lr_done:
    mov    eax, got
    ret
Log_ReadRaw ENDP

; ----------------------------------------------------------------------------
; Log_WriteRaw (internal) : create/overwrite a file with len bytes from pBuf
;   Out: EAX = ERR_OK or ERR_FILE_WRITE
; ----------------------------------------------------------------------------
Log_WriteRaw PROC,
    pPath:PTR BYTE, pBuf:PTR BYTE, len:DWORD

    LOCAL hFile:DWORD
    LOCAL written:DWORD

    mov    edx, pPath
    call   CreateOutputFile
    cmp    eax, INVALID_HANDLE_VALUE
    je     lw_fail
    mov    hFile, eax

    mov    eax, hFile
    mov    edx, pBuf
    mov    ecx, len
    call   WriteToFile
    mov    written, eax

    mov    eax, hFile
    call   CloseFile

    mov    eax, written
    cmp    eax, len
    jne    lw_fail
    xor    eax, eax
    ret
lw_fail:
    mov    eax, ERR_FILE_WRITE
    ret
Log_WriteRaw ENDP

; ----------------------------------------------------------------------------
; Log_Write : add one timestamped line to the log
;   In : pText = zero-terminated text (at most 1000 characters)
;   Out: EAX   = ERR_OK, ERR_BUF_SMALL (text too long), ERR_LOG_FULL,
;                or ERR_FILE_WRITE
; ----------------------------------------------------------------------------
Log_Write PROC,
    pText:PTR BYTE

    LOCAL lineLen:DWORD
    LOCAL oldLen:DWORD

    INVOKE Str_length, pText
    cmp    eax, 1000
    ja     lg_too_long

    ; ---- build "[timestamp] text<CR><LF>" in lineBuf ----------------------------
    INVOKE Log_Timestamp, ADDR tsBuf
    mov    BYTE PTR lineBuf, 0
    INVOKE Util_StrCat, ADDR lineBuf, ADDR txtOpen
    INVOKE Util_StrCat, ADDR lineBuf, ADDR tsBuf
    INVOKE Util_StrCat, ADDR lineBuf, ADDR txtClose
    INVOKE Util_StrCat, ADDR lineBuf, pText
    INVOKE Util_StrCat, ADDR lineBuf, ADDR txtCRLF
    INVOKE Str_length, ADDR lineBuf
    mov    lineLen, eax

    ; ---- read the old log, append the line, write everything back ---------------
    INVOKE Log_ReadRaw
    mov    oldLen, eax
    add    eax, lineLen
    cmp    eax, LOG_BUF_SIZE
    ja     lg_full

    mov    edx, OFFSET logBuf
    add    edx, oldLen                      ; where the new line goes
    INVOKE Util_MemCopy, edx, ADDR lineBuf, lineLen
    mov    eax, oldLen
    add    eax, lineLen                     ; new total size
    INVOKE Log_WriteRaw, ADDR logPath, ADDR logBuf, eax
    ret
lg_too_long:
    mov    eax, ERR_BUF_SMALL
    ret
lg_full:
    mov    eax, ERR_LOG_FULL
    ret
Log_Write ENDP

; ----------------------------------------------------------------------------
; Log_Read : copy the whole log into the caller's buffer (zero-terminated)
;   In : pOut, maxOut = its size, pOutLen = receives the text length (or NULL)
;   Out: EAX = ERR_OK, or ERR_BUF_SMALL if the text was cut to fit
; ----------------------------------------------------------------------------
Log_Read PROC USES ebx,
    pOut:PTR BYTE, maxOut:DWORD, pOutLen:PTR DWORD

    LOCAL cutFlag:DWORD

    mov    cutFlag, 0
    cmp    maxOut, 0
    je     rd_small
    INVOKE Log_ReadRaw
    mov    ebx, eax                  ; EBX = bytes in the log
    mov    ecx, maxOut
    dec    ecx                       ; room for the text (one byte kept for the 0)
    cmp    ebx, ecx
    jbe    rd_fits
    mov    ebx, ecx                  ; too long: keep only what fits
    mov    cutFlag, 1
rd_fits:
    INVOKE Util_MemCopy, pOut, ADDR logBuf, ebx
    mov    edx, pOut
    mov    BYTE PTR [edx + ebx], 0
    mov    edx, pOutLen
    test   edx, edx
    jz     rd_no_len
    mov    [edx], ebx
rd_no_len:
    cmp    cutFlag, 0
    jne    rd_small
    xor    eax, eax
    ret
rd_small:
    mov    eax, ERR_BUF_SMALL
    ret
Log_Read ENDP

; ----------------------------------------------------------------------------
; Log_Clear : empty the log (the file is re-created with 0 bytes)
; ----------------------------------------------------------------------------
Log_Clear PROC
    INVOKE Log_WriteRaw, ADDR logPath, ADDR logBuf, 0
    ret
Log_Clear ENDP

; ----------------------------------------------------------------------------
; Log_Backup : copy the log to a backup file, then start a new empty log
;   In : pNameInOut = buffer of at least 64 bytes.
;        If it already holds a name, that name is used.
;        If it is empty, a name like  stego_log_20261015_140322.txt  is made
;        from the current time and written back into the buffer.
;   Out: EAX = ERR_OK, ERR_LOG_EMPTY (nothing to back up) or ERR_FILE_WRITE
; The first line of the NEW log says where the old log went.
; ----------------------------------------------------------------------------
Log_Backup PROC USES ebx esi edi,
    pNameInOut:PTR BYTE

    LOCAL len:DWORD

    INVOKE Log_ReadRaw
    mov    len, eax
    test   eax, eax
    jz     bk_empty

    mov    eax, pNameInOut
    cmp    BYTE PTR [eax], 0
    jne    bk_have_name              ; caller supplied a name

    ; ---- build the automatic name: prefix + YYYYMMDD_HHMMSS + suffix -----------
    INVOKE Log_Timestamp, ADDR tsBuf
    INVOKE Str_copy, ADDR bakPrefix, pNameInOut
    INVOKE Str_length, pNameInOut
    mov    edi, pNameInOut
    add    edi, eax                  ; EDI -> end of the prefix
    mov    esi, OFFSET tsBuf
bk_loop:
    mov    al, [esi]
    test   al, al
    jz     bk_loop_done
    cmp    al, ' '
    je     bk_underscore             ; the space between date and time
    cmp    al, '0'
    jb     bk_skip                   ; skip '-' and ':'
    cmp    al, '9'
    ja     bk_skip
    mov    [edi], al                 ; keep the digits
    inc    edi
    jmp    bk_skip
bk_underscore:
    mov    BYTE PTR [edi], '_'
    inc    edi
bk_skip:
    inc    esi
    jmp    bk_loop
bk_loop_done:
    mov    BYTE PTR [edi], 0
    INVOKE Util_StrCat, pNameInOut, ADDR bakSuffix

bk_have_name:
    INVOKE Log_WriteRaw, pNameInOut, ADDR logBuf, len
    test   eax, eax
    jnz    bk_ret                    ; could not write the backup: keep the log
    INVOKE Log_Clear
    test   eax, eax
    jnz    bk_ret

    mov    BYTE PTR noteBuf, 0       ; first line of the new log
    INVOKE Util_StrCat, ADDR noteBuf, ADDR txtNewLog
    INVOKE Util_StrCat, ADDR noteBuf, pNameInOut
    INVOKE Log_Write, ADDR noteBuf
    xor    eax, eax
    ret
bk_empty:
    mov    eax, ERR_LOG_EMPTY
bk_ret:
    ret
Log_Backup ENDP

END
