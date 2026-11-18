; ============================================================================
; crc32.asm  -  table-driven CRC-32 (the checksum used by ZIP, PNG, Ethernet)
; ----------------------------------------------------------------------------
; The CRC detects ACCIDENTAL damage to the hidden message. It is not a
; security feature: anyone can recompute it after changing the message.
;
; Algorithm (reflected, polynomial 0EDB88320h):
;   table[i]  : for each i = 0..255, take i and 8 times do
;                 if lowest bit is 1:  c = (c >> 1) XOR 0EDB88320h
;                 else:                c =  c >> 1
;   crc       : start with 0FFFFFFFFh; for each data byte b
;                 crc = (crc >> 8) XOR table[(crc XOR b) AND 0FFh]
;               finish with  NOT crc
; Check value: CRC-32("123456789") = 0CBF43926h
; ============================================================================
INCLUDE stego.inc

.data?
crcTable   DWORD 256 DUP(?)        ; the 256-entry lookup table
crcReady   DWORD ?                 ; 0 until the table has been built

.code

; ----------------------------------------------------------------------------
; Crc_Init : build the lookup table (only the first call does any work)
; ----------------------------------------------------------------------------
Crc_Init PROC USES eax ebx ecx

    cmp    crcReady, 0
    jne    c_done
    xor    ebx, ebx                 ; EBX = i = table index
c_outer:
    mov    eax, ebx                 ; c = i
    mov    ecx, 8                   ; 8 shift steps per entry
c_inner:
    shr    eax, 1                   ; CF = the bit shifted out
    jnc    c_noxor
    xor    eax, 0EDB88320h          ; bit was 1: apply the polynomial
c_noxor:
    dec    ecx
    jnz    c_inner
    mov    crcTable[ebx*4], eax     ; table[i] = c
    inc    ebx
    cmp    ebx, 256
    jb     c_outer
    mov    crcReady, 1
c_done:
    ret
Crc_Init ENDP

; ----------------------------------------------------------------------------
; Crc_UpdateByte : feed one byte into a running CRC
;   In : crc = running value (start with 0FFFFFFFFh), b = next data byte
;   Out: EAX = new running value (call NOT EAX after the last byte)
; Used by Pkt_Verify, which reads the message byte by byte out of the image.
; ----------------------------------------------------------------------------
Crc_UpdateByte PROC USES edx,
    crc:DWORD, b:DWORD

    cmp    crcReady, 0
    jne    u_ready
    INVOKE Crc_Init
u_ready:
    mov    eax, crc
    mov    edx, b
    xor    edx, eax
    and    edx, 0FFh                ; table index = (crc XOR b) AND FFh
    shr    eax, 8                   ; crc >> 8
    xor    eax, crcTable[edx*4]     ; XOR the table entry
    ret
Crc_UpdateByte ENDP

; ----------------------------------------------------------------------------
; Crc_Compute : CRC-32 of a whole buffer
;   In : pBuf, len     Out: EAX = CRC-32
; ----------------------------------------------------------------------------
Crc_Compute PROC USES ecx edx esi,
    pBuf:PTR BYTE, len:DWORD

    INVOKE Crc_Init
    mov    esi, pBuf
    mov    ecx, len
    mov    eax, 0FFFFFFFFh          ; initial value
k_loop:
    test   ecx, ecx
    jz     k_done
    movzx  edx, BYTE PTR [esi]
    xor    edx, eax
    and    edx, 0FFh
    shr    eax, 8
    xor    eax, crcTable[edx*4]
    inc    esi
    dec    ecx
    jmp    k_loop
k_done:
    not    eax                      ; final XOR with 0FFFFFFFFh
    ret
Crc_Compute ENDP

END
