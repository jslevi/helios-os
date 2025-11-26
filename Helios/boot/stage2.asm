; - Runs in 16-bit real mode (loaded by stage1 at 0x0000:0x7E00)
; - Prints a message
; - Loads the kernel from disk into memory
; - Switches to 32-bit protected mode
; - Jumps to the kernel entry

[BITS 16]
[ORG 0x7E00]

; ----------------------------------------------------------------------
; Constants: adjust these to match your disk layout and kernel size
; ----------------------------------------------------------------------

KERNEL_LOAD_SEG       EQU 0x1000      ; where to load the kernel (segment)
KERNEL_LOAD_OFF       EQU 0x0000      ; offset within that segment
                                      ; linear = 0x1000 * 16 + 0x0000 = 0x00010000

KERNEL_START_SECTOR   EQU 6           ; CHS sector where kernel starts
                                      ; sector 1 = MBR (stage1)
                                      ; sectors 2-5 = stage2 (4 sectors)
                                      ; sector 6 onward = kernel (here)
KERNEL_SECTORS        EQU 32          ; number of sectors to read for kernel
                                      ; (32 * 512 = 16 KiB)

; GDT selector values (must match layout of GDT below)
CODE_SEL              EQU 0x08        ; first non-null descriptor
DATA_SEL              EQU 0x10        ; second non-null descriptor

; Kernel entry linear address in protected mode
KERNEL_ENTRY          EQU 0x00010000  ; beginning of loaded kernel

; ----------------------------------------------------------------------
; Entry from stage1 (CS:IP = 0x0000:0x7E00, DL = boot drive)
; ----------------------------------------------------------------------

start_stage2:
    cli

    ; Re-initialize segments and stack (defensive; stage1 already did this)
    xor     ax, ax
    mov     ds, ax
    mov     es, ax
    mov     ss, ax
    mov     sp, 0x7C00       ; simple stack in low memory

    sti

    ; Print status message
    mov     si, stage2_msg
    call    print_string

    ; ------------------------------------------------------------------
    ; Load kernel from disk using BIOS INT 13h (CHS)
    ;   ES:BX = destination buffer (0x1000:0x0000 = 0x00010000)
    ;   DL    = boot drive (still preserved from stage1)
    ; ------------------------------------------------------------------

    mov     ax, KERNEL_LOAD_SEG
    mov     es, ax
    mov     bx, KERNEL_LOAD_OFF

    mov     ah, 0x02             ; INT 13h, function 02h: read sectors
    mov     al, KERNEL_SECTORS   ; number of sectors to read
    mov     ch, 0                ; cylinder 0
    mov     dh, 0                ; head 0
    mov     cl, KERNEL_START_SECTOR   ; starting sector (6)
    ; DL already contains boot drive from BIOS/stage1
    int     0x13
    jc      disk_error_kernel    ; if CF=1, read failed

    ; Print "kernel loaded" message
    mov     si, kernel_ok_msg
    call    print_string

    ; ------------------------------------------------------------------
    ; Build and load GDT, then enter 32-bit protected mode
    ; ------------------------------------------------------------------

    cli

    ; Load GDT (descriptor defined below)
    lgdt    [gdt_descriptor]

    ; Enable protected mode: set PE bit (bit 0) in CR0
    mov     eax, cr0
    or      eax, 0x00000001
    mov     cr0, eax

    ; Far jump to flush prefetch queue and load 32-bit CS
    jmp     CODE_SEL:protected_mode_entry

; ----------------------------------------------------------------------
; 16-bit BIOS utilities
; ----------------------------------------------------------------------

; print_string: print a zero-terminated string at DS:SI using BIOS TTY
; Uses:
;   AH=0x0E, AL=char, BH=page, BL=attribute
; Preserves all registers (via pusha/popa).
print_string:
    pusha
.print_next:
    lodsb                       ; AL = [DS:SI], SI++
    test    al, al
    jz      .done
    mov     ah, 0x0E
    mov     bh, 0x00            ; page 0
    mov     bl, 0x07            ; light grey on black
    int     0x10
    jmp     .print_next
.done:
    popa
    ret

; ----------------------------------------------------------------------
; Disk error handler for kernel load
; ----------------------------------------------------------------------

disk_error_kernel:
    mov     si, kernel_fail_msg
    call    print_string
    cli
.halt:
    hlt
    jmp     .halt

; ----------------------------------------------------------------------
; 32-bit protected-mode entry
; ----------------------------------------------------------------------

[BITS 32]

protected_mode_entry:
    ; Set up segment registers to use our flat data descriptor
    mov     ax, DATA_SEL
    mov     ds, ax
    mov     es, ax
    mov     fs, ax
    mov     gs, ax
    mov     ss, ax

    ; Set up a simple stack in low memory (within 1 MiB)
    mov     esp, 0x00090000

    ; Optionally: we could do more setup here (paging, etc.)
    ; For now, just jump directly to loaded kernel.
    jmp     KERNEL_ENTRY

; If kernel ever returns, just hang
pm_halt:
    cli
.pm_loop:
    hlt
    jmp     .pm_loop

; ----------------------------------------------------------------------
; Global Descriptor Table (GDT)
; ----------------------------------------------------------------------

[BITS 16]                 ; data structures, not code bitness

gdt_start:
    ; Null descriptor (required)
    dq 0x0000000000000000

    ; Code segment descriptor: base = 0x00000000, limit = 0x000FFFFF (4 GiB),
    ; 32-bit, 4 KiB granularity, execute/read
    ; Access byte: 10011010b = 0x9A
    ; Flag/limit byte: 11001111b = 0xCF (G=1, D=1, L=0, AVL=0; limit high=0xF)
    dw 0xFFFF              ; limit low
    dw 0x0000              ; base low
    db 0x00                ; base middle
    db 10011010b           ; access
    db 11001111b           ; flags + limit high
    db 0x00                ; base high

    ; Data segment descriptor: base = 0, limit = 4 GiB, read/write
    ; Access byte: 10010010b = 0x92
    dw 0xFFFF              ; limit low
    dw 0x0000              ; base low
    db 0x00                ; base middle
    db 10010010b           ; access
    db 11001111b           ; flags + limit high
    db 0x00                ; base high

gdt_end:

; GDTR (GDT descriptor) used by LGDT
gdt_descriptor:
    dw gdt_end - gdt_start - 1   ; size of GDT minus 1
    dd gdt_start                 ; linear base address of GDT

; ----------------------------------------------------------------------
; Messages
; ----------------------------------------------------------------------

stage2_msg:        db "Helios stage2: loading kernel", 13, 10, 0
kernel_ok_msg:     db "Helios stage2: kernel loaded.", 13, 10, 0
kernel_fail_msg:   db "Helios stage2: kernel has failed to load.", 13, 10, 0

; ----------------------------------------------------------------------
; End of stage2 (no fixed size requirement here, but must fit in the
; number of sectors STAGE2_SECTORS that stage1 reads for it).
; ----------------------------------------------------------------------
