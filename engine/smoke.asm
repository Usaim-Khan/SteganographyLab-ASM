; ============================================================================
; smoke.asm  -  Step 0 smoke test (temporary; delete after Step 1 works)
; ----------------------------------------------------------------------------
; Purpose: prove that Irvine32 FILE procedures (OpenInputFile, ReadFromFile,
;          CloseFile) work when called from BOTH the console menu and the
;          FLTK GUI. If this works from the GUI, no C++ file fallback is needed.
; ============================================================================
INCLUDE stego.inc

.code

; ----------------------------------------------------------------------------
; Stego_SmokeTest  (STDCALL)
;   Opens a file, reads its first 2 bytes, checks they are 'B','M', closes it.
;   In : pPath  - pointer to zero-terminated path
;   Out: EAX    - ERR_OK / ERR_FILE_OPEN / ERR_FILE_READ / ERR_NOT_BMP
;   Preserves: EBX (via USES). EAX, ECX, EDX are free to change in STDCALL.
; Irvine32 conventions used here:
;   OpenInputFile : EDX = path          -> EAX = handle (INVALID_HANDLE_VALUE on error)
;   ReadFromFile  : EAX = handle, EDX = buffer, ECX = count
;                   -> EAX = bytes read, CF set on error
;   CloseFile     : EAX = handle
; ----------------------------------------------------------------------------
Stego_SmokeTest PROC USES ebx,
    pPath:PTR BYTE

    LOCAL hdr[4]:BYTE              ; room for the first bytes of the file
    LOCAL result:DWORD             ; return code, kept so we can close the file first

    mov  result, ERR_OK

    ; --- 1. open the file ---------------------------------------------------
    mov  edx, pPath
    call OpenInputFile
    cmp  eax, INVALID_HANDLE_VALUE
    jne  opened
    mov  eax, ERR_FILE_OPEN        ; nothing to close, return directly
    jmp  done

opened:
    mov  ebx, eax                  ; EBX = file handle for the rest of the proc

    ; --- 2. read the first two bytes ---------------------------------------
    mov  eax, ebx
    lea  edx, hdr
    mov  ecx, 2
    call ReadFromFile
    jc   read_failed               ; CF = 1 -> API failure
    cmp  eax, 2
    jb   not_bmp                   ; fewer than 2 bytes -> cannot be a BMP

    ; --- 3. check the 'BM' signature ---------------------------------------
    cmp  hdr[0], 'B'
    jne  not_bmp
    cmp  hdr[1], 'M'
    jne  not_bmp
    jmp  close_it                  ; signature OK, result stays ERR_OK

read_failed:
    mov  result, ERR_FILE_READ
    jmp  close_it

not_bmp:
    mov  result, ERR_NOT_BMP

    ; --- 4. always close the file -------------------------------------------
close_it:
    mov  eax, ebx
    call CloseFile
    mov  eax, result

done:
    ret
Stego_SmokeTest ENDP

END
