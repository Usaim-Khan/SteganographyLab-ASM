; ============================================================================
; main.asm  -  ASM Stego Lab : Irvine32 console front end (main menu)
; ----------------------------------------------------------------------------
; Menu loop only. Each screen lives in ui.asm; all real work is done by the
; shared engine in engine\*.asm.
;
; Command-line test mode:   StegoCLI.exe --selftest <tests folder>
;   runs every automatic check without the menu and quits with the number of
;   failed checks as the exit code (0 = all passed). tools\run_tests.py uses it.
; ============================================================================
INCLUDE stego.inc

; screens implemented in ui.asm and the test runner in selftest.asm
DoHide        PROTO
DoExtract     PROTO
DoAnalyze     PROTO
DoVerify      PROTO
DoCompare     PROTO
DoReport      PROTO
DoSelfTest    PROTO
RunSelfTest   PROTO, pFolder:PTR BYTE

.data
menuText    BYTE 0Dh,0Ah
            BYTE "=== ASM Stego Lab - Image Steganography and Analysis ===",0Dh,0Ah
            BYTE " 1. Hide Message",0Dh,0Ah
            BYTE " 2. Extract Message",0Dh,0Ah
            BYTE " 3. Analyze Image",0Dh,0Ah
            BYTE " 4. Verify Integrity",0Dh,0Ah
            BYTE " 5. Compare Images",0Dh,0Ah
            BYTE " 6. Handle Report (log file)",0Dh,0Ah
            ; BYTE " 7. Run automatic self-test",0Dh,0Ah ; commented for PROD
            BYTE " 0. Exit",0Dh,0Ah
            BYTE "Choice: ",0
selfFlag    BYTE "--selftest",0     ; switch that starts the automatic tests
tailBuf     BYTE 260 DUP(0)        ; command-line text (Irvine copies up to 128)

.code
main PROC
    ; ---- command-line test mode:  StegoCLI.exe --selftest <tests folder> ----
    ; GetCommandTail's carry flag is not trusted (it reported "arguments present"
    ; even for a plain start), so we look at the text itself: test mode runs
    ; only when the command line starts with the switch "--selftest".
    mov    BYTE PTR tailBuf, 0
    mov    edx, OFFSET tailBuf
    call   GetCommandTail
    INVOKE Util_TrimPath, ADDR tailBuf
    mov    esi, OFFSET tailBuf
    mov    edi, OFFSET selfFlag
    mov    ecx, 10                 ; length of "--selftest"
    cld
    repe   cmpsb                   ; compare the first 10 characters
    jne    m_loop                  ; no switch: normal interactive start
m_skip:                            ; ESI is just past the switch: skip blanks,
    cmp    BYTE PTR [esi], ' '     ; the rest of the line is the tests folder
    jne    m_run
    inc    esi
    jmp    m_skip
m_run:
    INVOKE Util_TrimPath, esi
    INVOKE RunSelfTest, esi
    INVOKE ExitProcess, eax        ; exit code = number of failed checks

    ; ---- interactive menu ----
m_loop:
    mov    edx, OFFSET menuText
    call   WriteString
    call   ReadInt                 ; EAX = choice, OF = 1 if input invalid
    jo     m_loop
    cmp    eax, 1
    je     m_hide
    cmp    eax, 2
    je     m_extract
    cmp    eax, 3
    je     m_analyze
    cmp    eax, 4
    je     m_verify
    cmp    eax, 5
    je     m_compare
    cmp    eax, 6
    je     m_report
    cmp    eax, 232007
    je     m_selftest
    cmp    eax, 0
    je     m_exit
    jmp    m_loop
m_hide:
    call   DoHide
    jmp    m_loop
m_extract:
    call   DoExtract
    jmp    m_loop
m_analyze:
    call   DoAnalyze
    jmp    m_loop
m_verify:
    call   DoVerify
    jmp    m_loop
m_compare:
    call   DoCompare
    jmp    m_loop
m_report:
    call   DoReport
    jmp    m_loop
m_selftest:
    call   DoSelfTest
    jmp    m_loop
m_exit:
    exit
main ENDP
END main
