; ============================================================================
; selftest.asm  -  automatic tests for the whole engine (CLI side)
; ----------------------------------------------------------------------------
; RunSelfTest runs every check below, prints PASS / FAIL lines and returns the
; number of FAILED checks in EAX (0 = everything passed).
;   Part A  Bmp_Load error codes on the generated test images
;   Part B  Pix_Index row-padding arithmetic
;   Part C  CRC-32 (known check value)
;   Part D  hide / extract / verify round trips, capacity limits, tampering
;   Part E  the same on an image whose rows have padding bytes
;   Part F  the Op_* operations, Analyze and Compare (MSE / PSNR)
;   Part G  the log file: write, read, backup
; The test images come from tools/make_test_bmps.py.
; ============================================================================
INCLUDE stego.inc

; One Bmp_Load test: file name + the error code we expect
TEST_CASE STRUCT
    pName     DWORD ?
    expected  DWORD ?
TEST_CASE ENDS

; One Pix_Index test: label, colour byte n, expected file offset
PIX_CASE STRUCT
    pName     DWORD ?
    pixN      DWORD ?
    pixOffset DWORD ?
PIX_CASE ENDS

.data
; ---- file names ---------------------------------------------------------------
fn01 BYTE "ok_4x4.bmp",0
fn02 BYTE "ok_5x3_padded.bmp",0
fn03 BYTE "ok_7x2_padded.bmp",0
fn04 BYTE "ok_1x1.bmp",0
fn05 BYTE "ok_topdown_5x3.bmp",0
fn06 BYTE "bad_notbm.bmp",0
fn07 BYTE "bad_empty.bmp",0
fn08 BYTE "bad_8bit.bmp",0
fn09 BYTE "bad_32bit.bmp",0
fn10 BYTE "bad_compressed.bmp",0
fn11 BYTE "bad_tiny.bmp",0
fn12 BYTE "bad_truncated.bmp",0
fn13 BYTE "bad_zero_width.bmp",0
fn14 BYTE "bad_toobig.bmp",0
fn15 BYTE "no_such_file.bmp",0        ; does not exist on purpose
fnHide   BYTE "hide_64x48.bmp",0      ; 64x48: no row padding, capacity 1140
fnPad    BYTE "hide_101x50_padded.bmp",0 ; rows have 1 padding byte, capacity 1881
fnEnc    BYTE "tmp_encoded.bmp",0     ; written by the tests

; ---- Part A table ---------------------------------------------------------------
tcTable TEST_CASE <OFFSET fn01, ERR_OK>
        TEST_CASE <OFFSET fn02, ERR_OK>
        TEST_CASE <OFFSET fn03, ERR_OK>
        TEST_CASE <OFFSET fn04, ERR_OK>
        TEST_CASE <OFFSET fn05, ERR_OK>
        TEST_CASE <OFFSET fn06, ERR_NOT_BMP>
        TEST_CASE <OFFSET fn07, ERR_NOT_BMP>
        TEST_CASE <OFFSET fn08, ERR_NOT_24BIT>
        TEST_CASE <OFFSET fn09, ERR_NOT_24BIT>
        TEST_CASE <OFFSET fn10, ERR_COMPRESSED>
        TEST_CASE <OFFSET fn11, ERR_BAD_SIZE>
        TEST_CASE <OFFSET fn12, ERR_BAD_SIZE>
        TEST_CASE <OFFSET fn13, ERR_BAD_SIZE>
        TEST_CASE <OFFSET fn14, ERR_TOO_BIG>
        TEST_CASE <OFFSET fn15, ERR_FILE_OPEN>
TEST_COUNT EQU ($ - tcTable) / SIZEOF TEST_CASE

; ---- Part B table: ok_5x3_padded.bmp (rowBytes 15, stride 16, offset 54) ---------
pn0  BYTE "Pix_Index(n=0)  -> offset",0
pn1  BYTE "Pix_Index(n=14) -> offset (last byte of row 0)",0
pn2  BYTE "Pix_Index(n=15) -> offset (first byte of row 1, skips padding)",0
pn3  BYTE "Pix_Index(n=29) -> offset",0
pn4  BYTE "Pix_Index(n=30) -> offset (first byte of row 2)",0
pn5  BYTE "Pix_Index(n=44) -> offset (last colour byte)",0
pn6  BYTE "Pix_Index(n=45) -> PIX_INVALID (one past the end)",0
pixTable PIX_CASE <OFFSET pn0, 0,  54>
         PIX_CASE <OFFSET pn1, 14, 68>
         PIX_CASE <OFFSET pn2, 15, 70>
         PIX_CASE <OFFSET pn3, 29, 84>
         PIX_CASE <OFFSET pn4, 30, 86>
         PIX_CASE <OFFSET pn5, 44, 100>
         PIX_CASE <OFFSET pn6, 45, PIX_INVALID>
PIX_COUNT EQU ($ - pixTable) / SIZEOF PIX_CASE

; ---- test names (one per check) ------------------------------------------------------
nmByteVal  BYTE "  byte stored at that offset = n mod 256 (not a padding byte)",0
nmPixLoad  BYTE "load ok_5x3_padded.bmp for the Pix_Index tests",0
nmCrc1     BYTE "CRC-32 of '123456789' = 0CBF43926h",0
nmCrc2     BYTE "CRC-32 of an empty buffer = 0",0
nmLoadH    BYTE "load hide_64x48.bmp",0
nmCap      BYTE "capacity of 64x48 = 1140 bytes",0
nmHide     BYTE "Pkt_Hide 'Hello, COAL!'",0
nmExt      BYTE "Pkt_Extract",0
nmExtLen   BYTE "extracted length = 12",0
nmExtEq    BYTE "extracted text equals the hidden text",0
nmVer      BYTE "Pkt_Verify says VALID",0
nmCrcStore BYTE "stored CRC equals Crc_Compute(message)",0
nmCrcCalc  BYTE "calculated CRC equals stored CRC",0
nmTamper   BYTE "after flipping one message bit Pkt_Verify says CORRUPTED",0
nmEmpty    BYTE "empty message is rejected (ERR_EMPTY_MSG)",0
nmTooBig   BYTE "message of 1141 bytes is rejected (capacity is 1140)",0
nmFull     BYTE "message of exactly 1140 bytes fits",0
nmFullExt  BYTE "extract the 1140-byte message",0
nmFullLen  BYTE "extracted length = 1140",0
nmFullEq   BYTE "1140-byte message extracted unchanged",0
nmFullVer  BYTE "1140-byte message verifies VALID",0
nmReload   BYTE "reload the clean cover image",0
nmNoSig    BYTE "clean image: Pkt_Extract finds no signature",0
nmNoSig2   BYTE "clean image: Pkt_Verify finds no signature",0
nmTinyCap  BYTE "tiny image (4x4) has capacity 0",0
nmLoadP    BYTE "load hide_101x50_padded.bmp",0
nmCapP     BYTE "capacity of 101x50 = 1881 bytes",0
nmHideP    BYTE "padded image: Pkt_Hide 1100 bytes",0
nmExtP     BYTE "padded image: Pkt_Extract",0
nmExtPEq   BYTE "padded image: message extracted unchanged",0
nmVerP     BYTE "padded image: Pkt_Verify says VALID",0
nmLog0     BYTE "Log_Clear",0
nmOpHide   BYTE "Op_Hide",0
nmSame     BYTE "Op_Hide refuses to overwrite the cover (ERR_SAME_FILE)",0
nmOpVer    BYTE "Op_Verify on the encoded image",0
nmOpExt    BYTE "Op_Extract on the encoded image",0
nmOpExtEq  BYTE "Op_Extract text equals the hidden text",0
nmAn1      BYTE "Op_Analyze (encoded): ok",0
nmAn2      BYTE "Op_Analyze: hidden message detected",0
nmAn3      BYTE "Op_Analyze: message length = 12",0
nmAn4      BYTE "Op_Analyze: width = 64",0
nmAn5      BYTE "Op_Analyze: height = 48",0
nmAn6      BYTE "Op_Analyze: capacity = 1140",0
nmAn7      BYTE "Op_Analyze (cover): ok",0
nmAn8      BYTE "Op_Analyze (cover): no hidden message",0
nmCmp1     BYTE "Op_Compare (cover vs encoded): ok",0
nmCmp2     BYTE "Compare: some bytes changed",0
nmCmp3     BYTE "Compare: at most 8 bits per packet byte changed (<= 192)",0
nmCmp4     BYTE "Compare: every changed byte differs in exactly one bit",0
nmCmp5     BYTE "Compare: largest difference = 1",0
nmCmp6     BYTE "Compare: sum of squares = changed bytes",0
nmCmp7     BYTE "Compare: not reported as identical",0
nmCmp8     BYTE "Compare: PSNR is at least 48 dB",0
nmCmp9     BYTE "Op_Compare (cover vs itself): ok",0
nmCmp10    BYTE "Compare: identical images are reported identical",0
nmCmp11    BYTE "Compare: different sizes -> ERR_SIZE_MISMATCH",0
nmLogLines BYTE "log holds 9 lines (one per operation)",0
nmBak      BYTE "Log_Backup to selftest_backup.txt",0
nmBakNew   BYTE "new log holds 1 line after the backup",0
nmBakOld   BYTE "backup file holds the 9 old lines",0
nmTs1      BYTE "Log_Timestamp is 19 characters long",0
nmTs2      BYTE "Log_Timestamp has a space after the date",0

; ---- other data -----------------------------------------------------------------------
msgTitleA  BYTE 0Dh,0Ah,"--- Part A: Bmp_Load on the test files ---",0Dh,0Ah,0
msgTitleB  BYTE 0Dh,0Ah,"--- Part B: Pix_Index with row padding ---",0Dh,0Ah,0
msgTitleC  BYTE 0Dh,0Ah,"--- Part C: CRC-32 ---",0Dh,0Ah,0
msgTitleD  BYTE 0Dh,0Ah,"--- Part D: hide / extract / verify ---",0Dh,0Ah,0
msgTitleE  BYTE 0Dh,0Ah,"--- Part E: image with padded rows ---",0Dh,0Ah,0
msgTitleF  BYTE 0Dh,0Ah,"--- Part F: operations, Analyze, Compare ---",0Dh,0Ah,0
msgTitleG  BYTE 0Dh,0Ah,"--- Part G: log file ---",0Dh,0Ah,0
msgPass    BYTE "  PASS  ",0
msgFail    BYTE "  FAIL  ",0
msgExpect  BYTE "   expected ",0
msgGot     BYTE "   got ",0
msgFolder  BYTE "Test folder: ",0
msgEmptyF  BYTE "(empty - the images are looked for next to the program)",0
msgHint    BYTE "HINT: 'got 1' means a test file could not be opened. Check the test folder above;",0Dh,0Ah
           BYTE "      it must contain the .bmp files made by tools\make_test_bmps.py.",0Dh,0Ah,0
msgResult  BYTE 0Dh,0Ah,"RESULT: ",0
msgAll     BYTE "ALL ",0
msgPassed  BYTE " CHECKS PASSED",0
msgOf      BYTE " of ",0
msgFailed  BYTE " CHECKS FAILED",0

helloMsg   BYTE "Hello, COAL!",0     ; 12 characters
crcInput   BYTE "123456789",0
backupName BYTE "selftest_backup.txt",0
testLog    BYTE "selftest_log.txt",0
const100   REAL8 100.0

gTotal     DWORD 0                   ; checks run so far
gFail      DWORD 0                   ; checks failed so far
gFolder    DWORD 0                   ; folder with the test images

.data?
fullPath   BYTE 300 DUP(?)           ; folder + "\" + file name
fullPath2  BYTE 300 DUP(?)
bigBuf     BYTE 1300 DUP(?)          ; test message pattern
outBuf     BYTE 2100 DUP(?)          ; extracted text
logText    BYTE 4096 DUP(?)          ; log contents
viS        VERIFYINFO <>
aiS        ANALYSISINFO <>
ciS        COMPAREINFO <>

.code

; Load a table entry address into ESI (uses EAX). idx is the caller's LOCAL.
LoadCasePtr MACRO
    mov    eax, idx
    shl    eax, 3                    ; TEST_CASE entries are 8 bytes
    lea    esi, tcTable
    add    esi, eax
ENDM
LoadPixPtr MACRO
    mov    eax, idx
    imul   eax, SIZEOF PIX_CASE      ; PIX_CASE entries are 12 bytes
    lea    esi, pixTable
    add    esi, eax
ENDM

; ----------------------------------------------------------------------------
; Chk : record one check. Prints PASS, or FAIL with the two numbers.
; ----------------------------------------------------------------------------
Chk PROC USES eax edx,
    pName:PTR BYTE, expected:DWORD, actual:DWORD

    inc    gTotal
    mov    eax, actual
    cmp    eax, expected
    jne    ck_bad
    mov    edx, OFFSET msgPass
    call   WriteString
    mov    edx, pName
    call   WriteString
    call   Crlf
    ret
ck_bad:
    inc    gFail
    mov    edx, OFFSET msgFail
    call   WriteString
    mov    edx, pName
    call   WriteString
    mov    edx, OFFSET msgExpect
    call   WriteString
    mov    eax, expected
    call   WriteDec
    mov    edx, OFFSET msgGot
    call   WriteString
    mov    eax, actual
    call   WriteDec
    call   Crlf
    ret
Chk ENDP

; StrEq : EAX = 1 if the two strings are equal, else 0
StrEq PROC,
    p1:PTR BYTE, p2:PTR BYTE

    INVOKE Str_compare, p1, p2
    jne    se_no
    mov    eax, 1
    ret
se_no:
    xor    eax, eax
    ret
StrEq ENDP

; CountChar : EAX = how many times character theChar occurs in the string pText
CountChar PROC USES esi,
    pText:PTR BYTE, theChar:DWORD

    xor    eax, eax
    mov    esi, pText
cc_loop:
    mov    dl, [esi]
    test   dl, dl
    jz     cc_done
    movzx  edx, dl
    cmp    edx, theChar
    jne    cc_next
    inc    eax
cc_next:
    inc    esi
    jmp    cc_loop
cc_done:
    ret
CountChar ENDP

; BuildPath : pDest = gFolder + "\" + pName  (backslash added if missing)
BuildPath PROC USES ebx,
    pName:PTR BYTE, pDest:PTR BYTE

    INVOKE Str_copy, gFolder, pDest
    INVOKE Str_length, pDest
    mov    ebx, eax                  ; EBX = length of the folder text
    test   ebx, ebx
    jz     bp_append                 ; empty folder: use the bare file name
    mov    edx, pDest
    cmp    BYTE PTR [edx + ebx - 1], '\'
    je     bp_append                 ; already ends with a backslash
    mov    BYTE PTR [edx + ebx], '\'
    inc    ebx
    mov    BYTE PTR [edx + ebx], 0
bp_append:
    mov    eax, pDest
    add    eax, ebx                  ; where the file name goes
    INVOKE Str_copy, pName, eax
    ret
BuildPath ENDP

; FillBig : bigBuf[i] = 'A' + (i mod 26) for the first 1300 bytes
FillBig PROC USES eax ecx edx esi
    xor    esi, esi
fb_loop:
    mov    eax, esi
    xor    edx, edx
    mov    ecx, 26
    div    ecx                       ; EDX = i mod 26
    add    edx, 'A'
    mov    bigBuf[esi], dl
    inc    esi
    cmp    esi, 1300
    jb     fb_loop
    ret
FillBig ENDP

; LoadTest : load file pName into slot 'slot' via fullPath; EAX = error
LoadTest PROC,
    pName:PTR BYTE, slot:DWORD

    INVOKE BuildPath, pName, ADDR fullPath
    INVOKE Bmp_Load, ADDR fullPath, slot
    ret
LoadTest ENDP

; ============================ Part A =========================================
TestFiles PROC USES esi
    LOCAL idx:DWORD
    LOCAL actual:DWORD

    mov    edx, OFFSET msgTitleA
    call   WriteString
    mov    idx, 0
tf_loop:
    cmp    idx, TEST_COUNT
    jae    tf_done
    LoadCasePtr
    INVOKE LoadTest, [esi].TEST_CASE.pName, SLOT_MAIN
    mov    actual, eax
    LoadCasePtr                      ; reload ESI: do not trust it after calls
    INVOKE Chk, [esi].TEST_CASE.pName, [esi].TEST_CASE.expected, actual
    inc    idx
    jmp    tf_loop
tf_done:
    ret
TestFiles ENDP

; ============================ Part B =========================================
TestPix PROC USES ebx esi
    LOCAL idx:DWORD
    LOCAL actual:DWORD
    LOCAL byteVal:DWORD

    mov    edx, OFFSET msgTitleB
    call   WriteString
    INVOKE LoadTest, ADDR fn02, SLOT_MAIN
    INVOKE Chk, ADDR nmPixLoad, ERR_OK, eax
    mov    idx, 0
tp_loop:
    cmp    idx, PIX_COUNT
    jae    tp_done
    INVOKE Bmp_GetInfo, SLOT_MAIN
    mov    ebx, eax                  ; EBX -> BMPINFO
    LoadPixPtr
    INVOKE Pix_Index, ebx, [esi].PIX_CASE.pixN
    mov    actual, eax
    LoadPixPtr
    INVOKE Chk, [esi].PIX_CASE.pName, [esi].PIX_CASE.pixOffset, actual

    LoadPixPtr
    cmp    [esi].PIX_CASE.pixOffset, PIX_INVALID
    je     tp_next                   ; nothing stored at an invalid offset
    INVOKE Bmp_GetInfo, SLOT_MAIN
    mov    ecx, [eax].BMPINFO.biBuffer
    test   ecx, ecx
    jz     tp_next                   ; image failed to load: nothing to read
    mov    eax, actual
    movzx  edx, BYTE PTR [ecx + eax] ; the byte at that file offset
    mov    byteVal, edx
    LoadPixPtr
    mov    eax, [esi].PIX_CASE.pixN
    and    eax, 0FFh                 ; test images store (n mod 256) in colour bytes
    INVOKE Chk, ADDR nmByteVal, eax, byteVal
tp_next:
    inc    idx
    jmp    tp_loop
tp_done:
    ret
TestPix ENDP

; ============================ Part C =========================================
TestCrc PROC
    mov    edx, OFFSET msgTitleC
    call   WriteString
    INVOKE Crc_Compute, ADDR crcInput, 9
    INVOKE Chk, ADDR nmCrc1, 0CBF43926h, eax
    INVOKE Crc_Compute, ADDR crcInput, 0
    INVOKE Chk, ADDR nmCrc2, 0, eax
    ret
TestCrc ENDP

; ============================ Part D =========================================
TestHide PROC USES ebx
    LOCAL outLen:DWORD
    LOCAL expectCrc:DWORD

    mov    edx, OFFSET msgTitleD
    call   WriteString
    INVOKE FillBig

    INVOKE LoadTest, ADDR fnHide, SLOT_MAIN
    INVOKE Chk, ADDR nmLoadH, ERR_OK, eax
    INVOKE Bmp_GetInfo, SLOT_MAIN
    INVOKE Pkt_Capacity, eax
    INVOKE Chk, ADDR nmCap, 1140, eax

    ; ---- round trip with a short message ----
    INVOKE Pkt_Hide, SLOT_MAIN, ADDR helloMsg, 12
    INVOKE Chk, ADDR nmHide, ERR_OK, eax
    INVOKE Pkt_Extract, SLOT_MAIN, ADDR outBuf, 2100, ADDR outLen
    INVOKE Chk, ADDR nmExt, ERR_OK, eax
    INVOKE Chk, ADDR nmExtLen, 12, outLen
    INVOKE StrEq, ADDR outBuf, ADDR helloMsg
    INVOKE Chk, ADDR nmExtEq, 1, eax
    INVOKE Pkt_Verify, SLOT_MAIN, ADDR viS
    INVOKE Chk, ADDR nmVer, ERR_OK, eax
    INVOKE Crc_Compute, ADDR helloMsg, 12
    mov    expectCrc, eax
    INVOKE Chk, ADDR nmCrcStore, expectCrc, viS.viStoredCrc
    INVOKE Chk, ADDR nmCrcCalc, viS.viStoredCrc, viS.viCalcCrc

    ; ---- tamper: flip the lowest bit of hidden byte 9 (inside the message) ----
    INVOKE Bmp_GetInfo, SLOT_MAIN
    mov    ebx, eax
    INVOKE Pix_ExtractByte, ebx, 9
    xor    eax, 1
    INVOKE Pix_EmbedByte, ebx, 9, eax
    INVOKE Pkt_Verify, SLOT_MAIN, ADDR viS
    INVOKE Chk, ADDR nmTamper, ERR_CRC_BAD, eax

    ; ---- length limits (the image still carries a packet; Hide overwrites it) ----
    INVOKE Pkt_Hide, SLOT_MAIN, ADDR helloMsg, 0
    INVOKE Chk, ADDR nmEmpty, ERR_EMPTY_MSG, eax
    INVOKE Pkt_Hide, SLOT_MAIN, ADDR bigBuf, 1141
    INVOKE Chk, ADDR nmTooBig, ERR_MSG_TOO_BIG, eax
    mov    bigBuf[1140], 0           ; terminator so StrEq can compare 1140 bytes
    INVOKE Pkt_Hide, SLOT_MAIN, ADDR bigBuf, 1140
    INVOKE Chk, ADDR nmFull, ERR_OK, eax
    INVOKE Pkt_Extract, SLOT_MAIN, ADDR outBuf, 2100, ADDR outLen
    INVOKE Chk, ADDR nmFullExt, ERR_OK, eax
    INVOKE Chk, ADDR nmFullLen, 1140, outLen
    INVOKE StrEq, ADDR outBuf, ADDR bigBuf
    INVOKE Chk, ADDR nmFullEq, 1, eax
    INVOKE Pkt_Verify, SLOT_MAIN, ADDR viS
    INVOKE Chk, ADDR nmFullVer, ERR_OK, eax

    ; ---- a clean image has no signature ----
    INVOKE LoadTest, ADDR fnHide, SLOT_MAIN
    INVOKE Chk, ADDR nmReload, ERR_OK, eax
    INVOKE Pkt_Extract, SLOT_MAIN, ADDR outBuf, 2100, ADDR outLen
    INVOKE Chk, ADDR nmNoSig, ERR_NO_SIG, eax
    INVOKE Pkt_Verify, SLOT_MAIN, ADDR viS
    INVOKE Chk, ADDR nmNoSig2, ERR_NO_SIG, eax

    ; ---- a 4x4 image is too small for any message ----
    INVOKE LoadTest, ADDR fn01, SLOT_MAIN
    INVOKE Bmp_GetInfo, SLOT_MAIN
    INVOKE Pkt_Capacity, eax
    INVOKE Chk, ADDR nmTinyCap, 0, eax
    ret
TestHide ENDP

; ============================ Part E =========================================
TestPadded PROC
    LOCAL outLen:DWORD

    mov    edx, OFFSET msgTitleE
    call   WriteString
    INVOKE FillBig
    mov    bigBuf[1100], 0
    INVOKE LoadTest, ADDR fnPad, SLOT_MAIN
    INVOKE Chk, ADDR nmLoadP, ERR_OK, eax
    INVOKE Bmp_GetInfo, SLOT_MAIN
    INVOKE Pkt_Capacity, eax
    INVOKE Chk, ADDR nmCapP, 1881, eax
    INVOKE Pkt_Hide, SLOT_MAIN, ADDR bigBuf, 1100
    INVOKE Chk, ADDR nmHideP, ERR_OK, eax
    INVOKE Pkt_Extract, SLOT_MAIN, ADDR outBuf, 2100, ADDR outLen
    INVOKE Chk, ADDR nmExtP, ERR_OK, eax
    INVOKE StrEq, ADDR outBuf, ADDR bigBuf
    INVOKE Chk, ADDR nmExtPEq, 1, eax
    INVOKE Pkt_Verify, SLOT_MAIN, ADDR viS
    INVOKE Chk, ADDR nmVerP, ERR_OK, eax
    ret
TestPadded ENDP

; ============================ Part F =========================================
TestOps PROC USES ebx
    LOCAL outLen:DWORD
    LOCAL psnr100:DWORD

    mov    edx, OFFSET msgTitleF
    call   WriteString

    ; the log used by these operations is a private test log, not the user's
    INVOKE Log_SetFile, ADDR testLog
    INVOKE Log_Clear
    INVOKE Chk, ADDR nmLog0, ERR_OK, eax

    INVOKE BuildPath, ADDR fnHide, ADDR fullPath     ; cover
    INVOKE BuildPath, ADDR fnEnc,  ADDR fullPath2    ; encoded output
    INVOKE Op_Hide, ADDR fullPath, ADDR fullPath2, ADDR helloMsg, 12
    INVOKE Chk, ADDR nmOpHide, ERR_OK, eax
    INVOKE Op_Hide, ADDR fullPath, ADDR fullPath, ADDR helloMsg, 12
    INVOKE Chk, ADDR nmSame, ERR_SAME_FILE, eax

    INVOKE Op_Verify, ADDR fullPath2, ADDR viS
    INVOKE Chk, ADDR nmOpVer, ERR_OK, eax
    INVOKE Op_Extract, ADDR fullPath2, ADDR outBuf, 2100, ADDR outLen
    INVOKE Chk, ADDR nmOpExt, ERR_OK, eax
    INVOKE StrEq, ADDR outBuf, ADDR helloMsg
    INVOKE Chk, ADDR nmOpExtEq, 1, eax

    ; ---- Analyze the encoded image and the cover ----
    INVOKE Op_Analyze, ADDR fullPath2, ADDR aiS
    INVOKE Chk, ADDR nmAn1, ERR_OK, eax
    INVOKE Chk, ADDR nmAn2, 1, aiS.aiHasMessage
    INVOKE Chk, ADDR nmAn3, 12, aiS.aiMsgLen
    INVOKE Chk, ADDR nmAn4, 64, aiS.aiWidth
    INVOKE Chk, ADDR nmAn5, 48, aiS.aiHeight
    INVOKE Chk, ADDR nmAn6, 1140, aiS.aiCapacity
    INVOKE Op_Analyze, ADDR fullPath, ADDR aiS
    INVOKE Chk, ADDR nmAn7, ERR_OK, eax
    INVOKE Chk, ADDR nmAn8, 0, aiS.aiHasMessage

    ; ---- Compare cover and encoded image ----
    INVOKE Op_Compare, ADDR fullPath, ADDR fullPath2, ADDR ciS
    INVOKE Chk, ADDR nmCmp1, ERR_OK, eax
    xor    ebx, ebx
    cmp    ciS.ciChangedBytes, 0
    seta   bl                        ; EBX = 1 if some bytes changed
    INVOKE Chk, ADDR nmCmp2, 1, ebx
    xor    ebx, ebx
    cmp    ciS.ciChangedBytes, 192
    setbe  bl                        ; EBX = 1 if changed bytes <= 192
    INVOKE Chk, ADDR nmCmp3, 1, ebx
    INVOKE Chk, ADDR nmCmp4, ciS.ciChangedBytes, ciS.ciChangedBits
    INVOKE Chk, ADDR nmCmp5, 1, ciS.ciMaxDiff
    INVOKE Chk, ADDR nmCmp6, ciS.ciChangedBytes, ciS.ciSumSqLo
    INVOKE Chk, ADDR nmCmp7, 0, ciS.ciIdentical
    fld    ciS.ciPsnr                ; PSNR in dB
    fmul   const100
    fistp  psnr100                   ; PSNR * 100 as an integer
    xor    ebx, ebx
    cmp    psnr100, 4800
    setae  bl                        ; EBX = 1 if PSNR >= 48.00 dB
    INVOKE Chk, ADDR nmCmp8, 1, ebx

    INVOKE Op_Compare, ADDR fullPath, ADDR fullPath, ADDR ciS
    INVOKE Chk, ADDR nmCmp9, ERR_OK, eax
    INVOKE Chk, ADDR nmCmp10, 1, ciS.ciIdentical

    INVOKE BuildPath, ADDR fnPad, ADDR fullPath2
    INVOKE Op_Compare, ADDR fullPath, ADDR fullPath2, ADDR ciS
    INVOKE Chk, ADDR nmCmp11, ERR_SIZE_MISMATCH, eax
    ret
TestOps ENDP

; ============================ Part G =========================================
TestLog PROC
    LOCAL len:DWORD

    mov    edx, OFFSET msgTitleG
    call   WriteString

    ; 9 operations ran in Part F, so the test log holds 9 lines (9 CR characters)
    INVOKE Log_Read, ADDR logText, 4096, ADDR len
    INVOKE CountChar, ADDR logText, 0Dh
    INVOKE Chk, ADDR nmLogLines, 9, eax

    INVOKE Log_Backup, ADDR backupName
    INVOKE Chk, ADDR nmBak, ERR_OK, eax
    INVOKE Log_Read, ADDR logText, 4096, ADDR len
    INVOKE CountChar, ADDR logText, 0Dh
    INVOKE Chk, ADDR nmBakNew, 1, eax      ; only the "New log started" line

    INVOKE Log_SetFile, ADDR backupName    ; read the backup file as if it were the log
    INVOKE Log_Read, ADDR logText, 4096, ADDR len
    INVOKE CountChar, ADDR logText, 0Dh
    INVOKE Chk, ADDR nmBakOld, 9, eax

    INVOKE Log_SetFile, 0                  ; back to the default log file name

    INVOKE Log_Timestamp, ADDR outBuf
    INVOKE Str_length, ADDR outBuf
    INVOKE Chk, ADDR nmTs1, 19, eax
    movzx  eax, outBuf[10]
    INVOKE Chk, ADDR nmTs2, ' ', eax
    ret
TestLog ENDP

; ----------------------------------------------------------------------------
; RunSelfTest
;   In : pFolder = folder that holds the test BMPs
;   Out: EAX     = number of failed checks (0 = all passed)
; ----------------------------------------------------------------------------
RunSelfTest PROC,
    pFolder:PTR BYTE

    mov    eax, pFolder
    mov    gFolder, eax
    mov    gTotal, 0
    mov    gFail, 0

    mov    edx, OFFSET msgFolder             ; tell the user which folder is used
    call   WriteString
    mov    edx, pFolder
    cmp    BYTE PTR [edx], 0
    jne    rs_show
    mov    edx, OFFSET msgEmptyF
rs_show:
    call   WriteString
    call   Crlf

    INVOKE TestFiles
    INVOKE TestPix
    INVOKE TestCrc
    INVOKE TestHide
    INVOKE TestPadded
    INVOKE TestOps
    INVOKE TestLog

    mov    edx, OFFSET msgResult
    call   WriteString
    cmp    gFail, 0
    jne    rs_some
    mov    edx, OFFSET msgAll
    call   WriteString
    mov    eax, gTotal
    call   WriteDec
    mov    edx, OFFSET msgPassed
    call   WriteString
    jmp    rs_end
rs_some:
    mov    edx, OFFSET msgHint
    call   WriteString
    mov    eax, gFail
    call   WriteDec
    mov    edx, OFFSET msgOf
    call   WriteString
    mov    eax, gTotal
    call   WriteDec
    mov    edx, OFFSET msgFailed
    call   WriteString
rs_end:
    call   Crlf
    mov    eax, gFail                ; return value = number of failures
    ret
RunSelfTest ENDP

END
