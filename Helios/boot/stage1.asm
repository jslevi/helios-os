; - Loaded by BIOS at 0x7C00
; - Loads a small stage2 loader from the next few sectors
; - Jumps to stage2 in real mode

BITS 16
ORG 0x7C00

; ----------------------------------------------------------------------
; Constants (adjust STAGE2_SECTORS if your stage2 grows)
; ----------------------------------------------------------------------

STAGE2_LOAD_SEG   EQU 0x0000        ; segment where we load stage2
STAGE2_LOAD_OFF   EQU 0x7E00        ; offset where we load stage2
STAGE2_SECTORS    EQU 4             ; how many sectors to read for stage2
                                    ; (sectors 2..(1+STAGE2_SECTORS))

; ----------------------------------------------------------------------
; Entry point (BIOS jumps here with CS:IP = 0x0000:0x7C00, DL = boot drive)
; ----------------------------------------------------------------------

start:
    cli

    ; Set up a flat-ish segment layout: all segments = 0
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x7C00          ; stack grows down from 0x7C00

    sti

    ; Save boot drive number (BIOS gives it in DL)
    mov [boot_drive], dl

    ; ------------------------------------------------------------------
    ; Load stage2 with BIOS INT 13h
    ; - We assume stage2 starts at LBA 1 (CH=0, DH=0, CL=2 → sector 2)
    ; - We read STAGE2_SECTORS sectors into ES:BX
    ; ------------------------------------------------------------------

    mov ax, STAGE2_LOAD_SEG
    mov es, ax
    mov bx, STAGE2_LOAD_OFF

load_stage2:
    mov ah, 0x02            ; INT 13h function 02h: read sectors
    mov al, STAGE2_SECTORS  ; number of sectors to read
    mov ch, 0               ; cylinder 0
    mov dh, 0               ; head 0
    mov cl, 2               ; sector 2 (sector 1 is this boot sector)
    mov dl, [boot_drive]    ; drive number (same as we booted from)
    int 0x13
    jc disk_error           ; if carry set, read failed

    ; ------------------------------------------------------------------
    ; Jump to stage2
    ; ------------------------------------------------------------------

    jmp STAGE2_LOAD_SEG:STAGE2_LOAD_OFF

; ----------------------------------------------------------------------
; Error handler: if disk read fails, just halt
; ----------------------------------------------------------------------

disk_error:
    cli
.hang:
    hlt
    jmp .hang

; ----------------------------------------------------------------------
; Data
; ----------------------------------------------------------------------

boot_drive: db 0

; ----------------------------------------------------------------------
; Padding + MBR signature
; ----------------------------------------------------------------------

TIMES 510-($-$$) db 0       ; pad up to 510 bytes
DW 0xAA55                   ; boot signature (little-endian 0x55AA)
