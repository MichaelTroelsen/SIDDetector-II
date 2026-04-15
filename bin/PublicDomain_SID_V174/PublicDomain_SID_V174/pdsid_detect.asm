; PDSID TOOL V1.1
; ============================================================================
; Dedicated tool for PDsid detection and configuration (RP2350 based)
; Handshake: Write 'P', 'D' to $D41D-$D41E. Read 'S' from $D41E.
; Mode Read: Write 'P', 'D'. Read Mode from $D41F.
; Mode Set:  Write 'P', 'D'. Write Mode (0=6581, 1=8580) to $D41F.

; KERNAL Routines
CHROUT  = $FFD2
GETIN   = $FFE4
SCNCLR  = $E544

; SID Register Addresses
SID_BASE        = $D400
REG_P    = SID_BASE + $1D
REG_D    = SID_BASE + $1E
REG_S    = SID_BASE + $1F

; Constants
RVS_ON          = 18
RVS_OFF         = 146
CR              = 13

; Zero Page
PTR_LO = $FB
PTR_HI = $FC

* = $0801 ; BASIC start
!byte $0b, $08, $ef, $00, $9e, $32, $30, $36, $31, $00, $00, $00 ; SYS 2061

main:
!zone main {
    jsr SCNCLR
    
    ; Check for PDsid presence first
    jsr check_pdsid
    bcc .found
    
    ; Not Found
    lda #<str_title
    ldy #>str_title
    jsr print_string
    
    lda #<str_not_found
    ldy #>str_not_found
    jsr print_string
    rts

.found:
    ; Main Logic
    
.refresh_screen:
    jsr SCNCLR
    
    lda #<str_title
    ldy #>str_title
    jsr print_string
    
    lda #<str_found
    ldy #>str_found
    jsr print_string
    
    ; 1. Read Current Mode
    jsr read_mode
    sta current_mode
    
    ; 2. Display Mode UI
    jsr display_mode_ui
    
    ; 3. Wait for Input
.input_loop:
    jsr GETIN
    beq .input_loop
    
    cmp #$31 ; '1'
    beq .set_6581
    cmp #$32 ; '2'
    beq .set_8580
    jmp .input_loop

.set_6581:
    lda #00
    jsr set_mode
    jmp .update
.set_8580:
    lda #01
    jsr set_mode
.update:
    ; Small delay to allow PDsid to process
    jsr delay
    jmp .refresh_screen
}

; ============================================================================
; SUBROUTINES
; ============================================================================

check_pdsid:
!zone check {
    sei
    ; Write 'P' to $D41D
    lda #$50
    sta REG_P
    ; Write 'D' to $D41E
    lda #$44
    sta REG_D
    
    ; Read from $D41E - Should be 'S' ($53)
    lda REG_D
    cli
    cmp #$53
    beq .success
    sec ; Set Carry = Failure
    rts
.success:
    clc ; Clear Carry = Success
    rts
}

read_mode:
!zone read {
    sei
    lda #$50
    sta REG_P
    lda #$44
    sta REG_D
    
    lda REG_S ; Read Mode from $D41F
    cli
    rts
}

set_mode:
!zone set {
    pha
    sei
    lda #$50
    sta REG_P
    lda #$44
    sta REG_D
    
    pla
    sta REG_S ; Write new mode
    cli
    rts
}

display_mode_ui:
!zone dui {
    lda #13
    jsr CHROUT
    
    lda #<str_current_mode
    ldy #>str_current_mode
    jsr print_string
    
    lda current_mode
    cmp #0
    bne .is_8580
    
    ; Mode is 6581
    lda #RVS_ON
    jsr CHROUT
    lda #<str_6581
    ldy #>str_6581
    jsr print_string
    lda #RVS_OFF
    jsr CHROUT
    
    lda #32 ; Space
    jsr CHROUT
    
    lda #<str_8580
    ldy #>str_8580
    jsr print_string
    jmp .menu

.is_8580:
    ; Mode is 8580
    lda #<str_6581
    ldy #>str_6581
    jsr print_string
    
    lda #32 ; Space
    jsr CHROUT
    
    lda #RVS_ON
    jsr CHROUT
    lda #<str_8580
    ldy #>str_8580
    jsr print_string
    lda #RVS_OFF
    jsr CHROUT

.menu:
    lda #<str_menu
    ldy #>str_menu
    jsr print_string
    rts
}

print_string:
!zone ps {
    sta PTR_LO
    sty PTR_HI
    ldy #0
.loop:
    lda (PTR_LO),y
    beq .done
    jsr CHROUT
    iny
    jmp .loop
.done:
    rts
}

delay:
!zone del {
    ldx #0
    ldy #0
.l1:
    iny
    bne .l1
    inx
    cpx #50 ; Wait approx (50*256) cycles
    bne .l1
    rts
}

; ============================================================================
; DATA
; ============================================================================
current_mode:   !byte 0

str_title:          !text "PDSID TOOL V1.1 - RP2350", 13, "------------------------", 13, 13, 0
str_not_found:      !text "PDSID NOT FOUND.", 13, 0
str_found:          !text "PDSID DETECTED!", 13, 0
str_current_mode:   !text 13, "CURRENT MODE: ", 0
str_6581:           !text " 6581 ", 0
str_8580:           !text " 8580 ", 0
str_menu:           !text 13, 13, "PRESS 1 OR 2 TO SWITCH MODE", 0
