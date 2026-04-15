* = $0801 
    !word $0801 
    !word $0DCC
    !byte   $9e
    !text "2061"
    !byte   0
; V1.10
; ARM2SID detection - done
; TC64 detection
; SFX Sound expander - half done
; MISTer C64
; 
;    
; V1.00
; problem:
; FPGA D400 og D500; you cannot poke FPGAsid for second(sid). Need to test with 2 physical sids. 
;------------------------------------------------------------------------------------------------------------
; todo:
; check for FCiii, and skip like 128 check!!
; unknown sid at D400, should also write in sid_list_h,low,type
; check SwinsidNano by eliminating others. Check if D400 and D500 is mirrored. NoSID will not mirror!!! 
; Turbo Chameleon also has sid emultaion and is detectable
; SFX Sound expander - x-soundfx.asm
; ARM2SID detection - x-arm2sid.asm
; MIDI test for frank Boz
; show sterosid of sidfx
; show sterosid of FPGASID
; show sterosid of ARM2SID
; ULTISID (U64) - asked
; MISTer C64 check
; MIDI Test
; DTV Test  
; 128 DCR test
; Swinsid Nano - lav high/low
; ----------------------------------------------------------------------------------------------------------
; test case
; D400: 6581 D500:Swindsid     - error
; D400: Swindsid D500:6581     - error
; D400: Swindsid DE00:6851     - error
; D400: 8580 D500:armsid       - 
; D400: armsid D500:8580       - error 
; D400: armsid DE00:8580       - error 
; D400: armsid D500:armsid     -  
; D400: Swindsid D500:Swindsid - 
; D400: armsid D500:Swindsid   - OK
; D400: armsid D420:Swindsid   - OK
; D400: 8580 DE00:6581         - OK 
; D400: fpgasid                - 
; D400: swinnano               - 
; D400: ultisid                - 
; D400: 128D                   - do not detect 128dcr
; ------------------------------------------------------------
; c:\debugger\1541u2.pl 192.168.0.146 -c run:"$(RunFilename)"
; ------------------------------------------------------------
 


    
; Master SID test program    
nmivec        = $0318                     ; NMI-vector
readkeyboard = $ffe4
data1 = $A4      
data2 = $A5
data3 = $A6
ZPbigloop   = $A3
ZPArrayPtr  = $A2
za7      =$a7
za8      =$a8
sidtype  =$a9
tmp2_zp  =$aa
tmp1_zp  =$ab
tmp_zp  =$ac
y_zp    =$ad
x_zp    =$ae

buf_zp  =$af
cnt2_zp  =$f6
sidnum_zp=$f7
cnt1_zp  =$f8

sptr_zp  = $f9 ; xx1B
sptr_zp1 = $fa ; d4xx

scnt_zp = $FB  ; hvad bruges den til?
mptr_zp = $fc  ; 00,20,40,60,80,A0,B0,C0,E0;
mptr_zp1 = $fd ; D4,D5,D6..DF
mcnt_zp = $fe  ; count  til 96
res_zp  = $ff

    
basend 
    !word 0 
    *=$080d


    
start           sei     
                ldx #$00
                lda #$00
init_sid_list:
                sta sid_list_h,x
                sta sid_list_l,x
                sta sid_list_t,x
                inx
                cpx #$08
                bne init_sid_list 
                
                JSR printscreen
                JSR checkpalntsc
                LDA $02a6 ; pal/ntsc
                beq cntsc                    ; if accu=0, then go to NTSC
                txs
                LDX #12    ; Select row 
                LDY #13    ; Select column 
                JSR $E50C   ; Set cursor 
                tsx
                lda #<pal_text
                ldy #>pal_text           ; otherwise print PAL-text
                jsr  $AB1E                   ; and go back.
                jmp check_cbmtype
cntsc:
                txs
                LDX #12    ; Select row 
                LDY #13    ; Select column 
                JSR $E50C   ; Set cursor 
                tsx
                lda #<ntsc_text
                ldy #>ntsc_text          ; print NTSC-text
                jsr  $AB1E                   ; and go back.
check_cbmtype:
                jsr check128
                txs
                LDX #12    ; Select row 
                LDY #30    ; Select column 
                JSR $E50C   ; Set cursor 
                tsx
                lda za7     ;
                cmp #$FF
                bne c128_c128
                lda #<c64_text
                ldy #>c64_text          ; print c64-text
                jsr  $AB1E                   ; and go back.
                jmp ibegin
c128_c128
                lda za7     ;
                cmp #$FC
                bne c128_tc64
                lda #<c128_text
                ldy #>c128_text          ; print c128-text
                jsr  $AB1E                   ; and go back.
                jmp ibegin
c128_tc64
                lda #<tc64_text
                ldy #>tc64_text          ; print tc64 text
                jsr  $AB1E                   ; and go back.

                
ibegin                
                lda #$ff    ; make sure the check is not done on a bad line
iloop1          cmp $d012   ; Don't run it on a badline.
                bne iloop1
                ldx #$00    ;wait for SIDFX to finish initialization (>1200us)
iloop2          inx
                bne iloop2

                JSR DETECTSIDFX

                ldx data1
                cpx #$30 ; 
                bne nosidfxl
                txs
                LDX #09    ; Select row 
                LDY #13    ; Select column 
                JSR $E50C   ; Set cursor 
                tsx
                LDA #<sidfxu 
                LDY #>sidfxu 
                jmp sidfxprint 
nosidfxl
                txs
                LDX #09    ; Select row 
                LDY #13    ; Select column 
                JSR $E50C   ; Set cursor 
                tsx
                LDA #<nosidfxu 
                LDY #>nosidfxu 
sidfxprint
                jsr $AB1E
                lda     #$00
                sta     sptr_zp         ; store lowbyte 00 (Sidhome)
                lda     #$D4            ; load highbyte D4  (Sidhome)
                sta     sptr_zp+1       ; store highbyte D4 (Sidhome)
                jsr Checkarmsid     
                ldx data1
                cpx #04 ; S
                bne armsid
                ; swinddectect
                txs
                LDX #05    ; Select row 
                LDY #13    ; Select column 
                JSR $E50C   ; Set cursor 
                tsx
                LDA #<swinsidUf 
                LDY #>swinsidUf 
                jsr $AB1E
                jmp end 
armsid:
                ldx data1
                cpx #05 ; N
                bne fpgasid
                ldx data2
                cpx #$4f ; O
                bne fpgasid
                ldx data3;
                cpx #$53 ; R
                bne armsidlo
                ; arm2sid detect
                txs
                LDX #04    ; Select row 
                LDY #13    ; Select column 
                JSR $E50C   ; Set cursor 
                LDA #<arm2sidf 
                LDY #>arm2sidf 
                jsr $AB1E 
                jmp end
                tsx
armsidlo:                
                ; armsid detect
                txs
                LDX #04    ; Select row 
                LDY #13    ; Select column 
                JSR $E50C   ; Set cursor 
                tsx
                LDA #<armsidf 
                LDY #>armsidf 
                jsr $AB1E 
                jmp end
                
fpgasid:
                lda #$00
                sta sptr_zp         ; store lowbyte 00 (Sidhome)
                lda #$d4            ; load highbyte D4  (Sidhome)
                sta sptr_zp+1       ; store highbyte D4 (Sidhome)
                jsr checkfpgasid
                ldx data1
                cpx #$06
                bne fpgasidf_6581_l ; hvis ikke 3F hop til 
                txs
                LDX #06    ; Select row 
                LDY #13    ; Select column 
                tsx
                JSR $E50C   ; Set cursor 
                LDA #<fpgasidf_8580u 
                LDY #>fpgasidf_8580u
                jsr $AB1E
                jmp end  
fpgasidf_6581_l:
                ldx data1
                cpx #$07
                bne checkphysical   ; hvis ikke 0 so nosound
                txs
                LDX #06    ; Select row 
                LDY #13    ; Select column 
                JSR $E50C   ; Set cursor 
                tsx
                LDA #<fpgasidf_6581u 
                LDY #>fpgasidf_6581u 
                jsr $AB1E 
                jmp end          
checkphysical:
                lda     #$00
                sta     sptr_zp         ; store lowbyte 00 (Sidhome)
                lda     #$d4            ; load highbyte D4  (Sidhome)
                sta     sptr_zp+1       ; store highbyte D4 (Sidhome)
                jsr checkrealsid
                ldx data1
                cpx #$01
                bne checkphysical_8580   ; hvis ikke 0 so nosound
                txs
                LDX #07    ; Select row 
                LDY #13    ; Select column 
                JSR $E50C   ; Set cursor 
                tsx
                LDA #<l6581f 
                LDY #>l6581f 
                jsr $AB1E 
                jmp end                
checkphysical_8580:
                ldx data1
                cpx #$02
                bne checkphysical2   ; hvis ikke 0 so nosound
                txs
                LDX #08    ; Select row 
                LDY #13    ; Select column 
                JSR $E50C   ; Set cursor 
                tsx
                LDA #<l8580f 
                LDY #>l8580f 
                jsr $AB1E 
                jmp end                
checkphysical2:
                lda #$00
                sta mptr_zp         ; store lowbyte 00 (Sidhome)
                lda #$d4            ; load highbyte D4  (Sidhome)
                sta mptr_zp+1       ; store highbyte D4 (Sidhome)
                jsr checksecondsid
                ldx data1
                cpx #$10
                bne swinmicro   ; hvis ikke 0 so nosound
                txs
                LDX #10    ; Select row 
                LDY #13    ; Select column 
                JSR $E50C   ; Set cursor 
                tsx
                LDA #<unknownsid 
                LDY #>unknownsid 
                jsr $AB1E 
                jmp end                
swinmicro:
                ;jsr checkswinmicro    ; false detect in boards with no sid.
                jmp nosound 
                ldx data1
                cpx #$08
                bne nosound   ; hvis ikke 0 so nosound
                txs
                LDX #05    ; Select row 
                LDY #13    ; Select column 
                JSR $E50C   ; Set cursor 
                tsx
                LDA #<swinsidnanof 
                LDY #>swinsidnanof 
                jsr $AB1E
                jmp end          
nosound:
                txs
                LDX #10    ; Select row 
                LDY #13    ; Select column 
                JSR $E50C   ; Set cursor 
                tsx
                LDA #<nosoundf 
                LDY #>nosoundf 
                jsr $AB1E 
                
end
                ; call for armsid
                ; sidnum_zp
                lda #$00
                sta sidnum_zp ; num_sids = 0
                
                lda #$05            ; armsid or swinsid
                sta sidtype    
                jsr sidstereostart
 
                lda #$06            ; FPGAsid
                sta sidtype    
                jsr sidstereostart
              
                lda #$01            ; 6581 or 8580
                sta sidtype    
                jsr sidstereostart
              ; print
                jsr sidstereo_print       
              ; funny decay check
                jsr calcandloop
funny_print:    
                LDX #11    ; Select row 
                LDY #13    ; Select column 
                JSR $E50C   ; Set cursor 
                jsr checktypeandprint
                ; sæt farve sort
                lda #01     ; black
                STA $0286   ; text color
                LDX #00    ; Select row 
                LDY #00    ; Select column 
                JSR $E50C   ; Set cursor 
                LDA #<sblank 
                LDY #>sblank 
                jsr $AB1E 
                
;debugm2         jsr readkeyboard
;                beq debugm2

readkey2              
           LDX #<IRQ
           LDY #>IRQ
           LDA #$00
           STX $0314  ; Vector to IRQ Interrupt Routine
           STY $0315  ; Vector to IRQ Interrupt Routine
           STA $D012  ; Read Current Raster Scan Line
           LDA #$7F
           STA $DC0D  ; Interrupt Control Register
           LDA #$1B
           STA $D011  ; Vertical Fine Scrolling and Control Register
           LDA #$01
           STA $D01A  ; IRQ Mask Register
           CLI        ; clear interupt
           JMP *      ; JMP til sig selv?

IRQ        INC $D019 ; VIC Interrupt Flag Register
           LDA #$00
           STA $D012 ; Read Current Raster Scan Line
           JSR COLWASH 
           JSR SPACEBARPROMPT ;As always an intro should have a spacebar prompt           
           JMP $EA7E

;Setup and allow the space bar to be pressed in order
;to exit the intro and run a code reloc/transfer subroutine

SPACEBARPROMPT
                LDA $DC01
                CMP #$EF
                BNE NOSPACEBARPRESSED
                lda $d012 ;load the current raster line into the accumulator
                cmp $d012 ;check if it has changed
                beq *-3
                JMP start 
NOSPACEBARPRESSED
                RTS

              
EXITINTRO
           jsr $E544 ;clear the screen
           LDA #$81
           STX $0314
           STY $0315
           STA $DC0D
           STA $DD0D
           LDA #$00
           STA $D019
           STA $D01A
           JSR $FF81 ;Blue border+blue screen clear
           jmp $E37B ; jump to basic
              
;-------------------------------------------------------------------------
printscreen:
    jsr $E544 ;clear the screen
    lda #00     ; black
    sta $D020
    sta $D021
    lda #07     ; yellow
    STA $0286   ; text color
    

    ldx #0
lp:
    lda screen,x
    sta $0400,x
    lda screen+$0100,x
    sta $0500,x
    lda screen+$0200,x
    sta $0600,x
    lda screen+$02e8,x
    sta $06e8,x
    lda #1
    sta $d800,x
    sta $d900,x
    sta $da00,x
    sta $dae8,x
    inx
    bne lp
    rts
;-------------------------------------------------------------------------

Checkarmsid     
                stx     x_zp            ; $ad 
                sty     y_zp            ; $ae
                pha                     ; 

;                sta     sptr_zp         ; load lowbyte 00  (Sidhome)
;                sta     sptr_zp+1       ; store highbyte D4 (Sidhome)
; -- hack --
;                ldy     sptr_zp
;                ldx     sptr_zp+1
                
                lda     sptr_zp+1
                sta     cas_d418+2      ; timing issue requieres runtime mod of upcodes.
                sta     cas_d418_1+2      ; timing issue requieres runtime mod of upcodes.
                sta     cas_d418_2+2      ; timing issue requieres runtime mod of upcodes.
                sta     cas_d418_3+2      ; timing issue requieres runtime mod of upcodes.
                sta     cas_d418_4+2      ; timing issue requieres runtime mod of upcodes.
                sta     cas_d418_5+2      ; timing issue requieres runtime mod of upcodes.
                sta     cas_d41D+2      ; timing issue requieres runtime mod of upcodes.
                sta     cas_d41D_1+2      ; timing issue requieres runtime mod of upcodes.
                sta     cas_d41D_2+2      ; timing issue requieres runtime mod of upcodes.
                sta     cas_d41D_3+2      ; timing issue requieres runtime mod of upcodes.
                sta     cas_d41D_4+2      ; timing issue requieres runtime mod of upcodes.
                sta     cas_d41D_5+2      ; timing issue requieres runtime mod of upcodes.
                sta     cas_d41D_6+2      ; timing issue requieres runtime mod of upcodes.
                sta     cas_d41B+2      ; timing issue requieres runtime mod of upcodes.
                sta     cas_d41C+2      ; timing issue requieres runtime mod of upcodes.
                sta     cas_d41E+2      ; timing issue requieres runtime mod of upcodes.
                sta     cas_d41E_3+2      ; timing issue requieres runtime mod of upcodes.
                sta     cas_d41E_4+2      ; timing issue requieres runtime mod of upcodes.
                sta     cas_d41E_5+2      ; timing issue requieres runtime mod of upcodes.
                sta     cas_d41F+2      ; timing issue requieres runtime mod of upcodes.
                sta     cas_d41F_3+2      ; timing issue requieres runtime mod of upcodes.
                sta     cas_d41F_4+2      ; timing issue requieres runtime mod of upcodes.
                sta     cas_d41F_5+2      ; timing issue requieres runtime mod of upcodes.
;
                lda     sptr_zp
                CLC
                ADC     #$18            ; Voice 3 control at D418
                sta     cas_d418+1      ; timing issue requieres runtime mod of upcodes.
                sta     cas_d418_1+1      ; timing issue requieres runtime mod of upcodes.
                sta     cas_d418_2+1      ; timing issue requieres runtime mod of upcodes.
                sta     cas_d418_3+1      ; timing issue requieres runtime mod of upcodes.
                sta     cas_d418_4+1      ; timing issue requieres runtime mod of upcodes.
                sta     cas_d418_5+1      ; timing issue requieres runtime mod of upcodes.
                lda     sptr_zp
                CLC
                ADC     #$1D            ; Voice 3 control at D418
                sta     cas_d41D+1      ; timing issue requieres runtime mod of upcodes.
                sta     cas_d41D_1+1      ; timing issue requieres runtime mod of upcodes.
                sta     cas_d41D_2+1      ; timing issue requieres runtime mod of upcodes.
                sta     cas_d41D_3+1      ; timing issue requieres runtime mod of upcodes.
                sta     cas_d41D_4+1      ; timing issue requieres runtime mod of upcodes.
                sta     cas_d41D_5+1      ; timing issue requieres runtime mod of upcodes.
                sta     cas_d41D_6+1      ; timing issue requieres runtime mod of upcodes.
                lda     sptr_zp
                CLC
                ADC     #$1b            ; Voice 3 control at D418
                sta     cas_d41B+1      ; timing issue requieres runtime mod of upcodes.
                lda     sptr_zp
                CLC
                ADC     #$1C            ; Voice 3 control at D418
                sta     cas_d41C+1      ; timing issue requieres runtime mod of upcodes.
                lda     sptr_zp
                CLC
                ADC     #$1E            ; Voice 3 control at D418
                sta     cas_d41E+1      ; timing issue requieres runtime mod of upcodes.
                sta     cas_d41E_3+1      ; timing issue requieres runtime mod of upcodes.
                sta     cas_d41E_4+1      ; timing issue requieres runtime mod of upcodes.
                sta     cas_d41E_5+1      ; timing issue requieres runtime mod of upcodes.
                lda     sptr_zp
                CLC
                ADC     #$1F            ; Voice 3 control at D418
                sta     cas_d41F+1      ; timing issue requieres runtime mod of upcodes.
                sta     cas_d41F_3+1      ; timing issue requieres runtime mod of upcodes.
                sta     cas_d41F_4+1      ; timing issue requieres runtime mod of upcodes.
                sta     cas_d41F_5+1      ; timing issue requieres runtime mod of upcodes.
; -- hack --

                lda #0    ; 
cas_d418        sta $D418 ;
cas_d418_1      sta $D418 ;
cas_d418_2      sta $D418 ;
cas_d41D        sta $D41D ;
cas_d41D_1      sta $D41D ;
cas_d41D_2      sta $D41D ;
                sta data1
                sta data2 
                jsr loop1sek
                jsr loop1sek
                lda #68   ; D
cas_d41F        sta $D41F ;
                lda #73   ; I
cas_d41E        sta $D41E ;
                lda #83   ; S
cas_d41D_3      sta $D41D ;
                jsr loop1sek
                jsr loop1sek
cas_d41B        lda $D41b ; S=swin n=arm
                cmp #$53
                bne ch_s_1
                lda #$04
                sta data1
                jmp ch_s_3   
ch_s_1:
                cmp #$4E
                bne ch_s_2
                lda #$05
                sta data1
                jmp ch_s_3   
ch_s_2:
                lda #$F0    
                sta data1 ; 
ch_s_3:
cas_d41C        lda $D41c ; w=swin o=arm
                sta data2 ; 
                lda #0    ; 
cas_d41d7       lda $D41D ; R=arm2sid
                sta data3 ; 
                lda #0    ; 
cas_d418_3      sta $D418 ;
cas_d418_4      sta $D418 ;
cas_d418_5      sta $D418 ;
cas_d41D_6      sta $D41D ;
cas_d41D_4      sta $D41D ;
cas_d41D_5      sta $D41D ;
cas_d41E_3      sta $D41E ;
cas_d41E_4      sta $D41E ;
cas_d41E_5      sta $D41E ;
cas_d41F_3      sta $D41F ;
cas_d41F_4      sta $D41F ;
cas_d41F_5      sta $D41F ;
                jsr loop1sek          ; <--- D7 80
                jsr loop1sek

                ldx     x_zp            ; $ad 
                ldy     y_zp            ; $ae
                pla                     ; 
                rts
;-------------------------------------------------------------------------

checkfpgasid

                stx     x_zp            ; $ad 
                sty     y_zp            ; $ae
                pha                     ; 
    ; To do this enable configuration mode by writing the magic cookie, then set the identify bit in D41E
    ; Finally read out registers $19/25 and $1A/26 and check the result for the value $F51D. 245/29
    ; When the value matches, FPGASID is identified.
    ; set config mode.

                lda     sptr_zp+1
                sta     cfs_D419+2       ; timing issue requieres runtime mod of upcodes.
                sta     cfs_D419_1+2       ; timing issue requieres runtime mod of upcodes.
                sta     cfs_D419_2+2       ; timing issue requieres runtime mod of upcodes.
                sta     cfs_D41A+2       ; timing issue requieres runtime mod of upcodes.
                sta     cfs_D41A_1+2       ; timing issue requieres runtime mod of upcodes.
                sta     cfs_D41A_2+2       ; timing issue requieres runtime mod of upcodes.
                sta     cfs_D41E+2       ; timing issue requieres runtime mod of upcodes.
                sta     cfs_D41E_1+2       ; timing issue requieres runtime mod of upcodes.
                sta     cfs_D41F+2       ; timing issue requieres runtime mod of upcodes.

                lda     sptr_zp
                CLC
                ADC     #$19            ; Voice 3 control at D418
                sta     cfs_D419+1      ; timing issue requieres runtime mod of upcodes.
                sta     cfs_D419_1+1      ; timing issue requieres runtime mod of upcodes.
                sta     cfs_D419_2+1      ; timing issue requieres runtime mod of upcodes.
                lda     sptr_zp
                CLC
                ADC     #$1A            ; Voice 3 control at D418
                sta     cfs_D41A+1      ; timing issue requieres runtime mod of upcodes.
                sta     cfs_D41A_1+1      ; timing issue requieres runtime mod of upcodes.
                sta     cfs_D41A_2+1      ; timing issue requieres runtime mod of upcodes.
                lda     sptr_zp
                CLC
                ADC     #$1E            ; Voice 3 control at D418
                sta     cfs_D41E+1      ; timing issue requieres runtime mod of upcodes.
                sta     cfs_D41E_1+1      ; timing issue requieres runtime mod of upcodes.
                lda     sptr_zp
                CLC
                ADC     #$1F            ; Voice 3 control at D418
                sta     cfs_D41F+1       ; timing issue requieres runtime mod of upcodes.

                lda #$81
cfs_D419        sta $D419
                lda #$65
cfs_D41A        sta $D41A
                lda %10000000           ; set bit %10000000
cfs_D41E        sta $d41e 
                ; hvis F51D FGPA found
cfs_D419_1      lda $D419
                cmp #$1D
                bne fpgasidf_nosound
cfs_D41A_1      lda $D41A
                cmp #$F5
                bne fpgasidf_nosound
cfs_D41E_1      lda $D41e ; C9
cfs_D41F        lda $D41f ; hvis 3F=8580 00=6581
                cmp #$3f
                bne fpgasidf_6581
                lda #$06
                sta data1
                sta data2
                jmp fpgaclearmagic 
            fpgasidf_6581:    
                cmp #$00
                bne fpgasidf_nosound
                lda #$07
                sta data1
                sta data2
                jmp fpgaclearmagic
            fpgasidf_nosound:
                lda #$F0 ; not found
                sta data1
                sta data2
            fpgaclearmagic: 
                lda #$00
cfs_D419_2      sta $D419
cfs_D41A_2      sta $D41A
                
                ldx     x_zp            ; $ad 
                ldy     y_zp            ; $ae
                pla                     ; 
                rts

;-------------------------------------------------------------------------
checkrealsid:
; from https://github.com/GideonZ/1541ultimate/blob/master/software/6502/sidcrt/player/advanced/detection.asm
;                lda     #$0    ; 
;                sta     sptr_zp         ; load lowbyte 00  (Sidhome)
;                lda     #$d4            ; load highbyte D4  (Sidhome)
;                sta     sptr_zp+1       ; store highbyte D4 (Sidhome)

                stx     x_zp            ; $ad 
                sty     y_zp            ; $ae
                pha                     ; 
; -- hack --
;                ldy     sptr_zp
;                ldx     sptr_zp+1
                
                lda     sptr_zp+1
                sta     crs_d412+2      ; timing issue requieres runtime mod of upcodes.
                sta     crs_d412_1+2      ; timing issue requieres runtime mod of upcodes.
                sta     crs_d412_2+2      ; timing issue requieres runtime mod of upcodes.
                sta     crs_d40f+2      ; timing issue requieres runtime mod of upcodes.
                sta     crs_d40f_1+2      ; timing issue requieres runtime mod of upcodes.
                sta     crs_d41b+2      ; timing issue requieres runtime mod of upcodes.
                sta     crs_d41b_1+2      ; timing issue requieres runtime mod of upcodes.
                sta     crs_d41b_2+2      ; timing issue requieres runtime mod of upcodes.
                sta     crs_d41b_3+2      ; timing issue requieres runtime mod of upcodes.
                sta     crs_d41b_4+2      ; timing issue requieres runtime mod of upcodes.
;
                lda     sptr_zp
                CLC
                ADC     #$12            ; Voice 3 control at D418
                sta     crs_d412+1      ; timing issue requieres runtime mod of upcodes.
                sta     crs_d412_1+1      ; timing issue requieres runtime mod of upcodes.
                sta     crs_d412_2+1      ; timing issue requieres runtime mod of upcodes.
                lda     sptr_zp
                CLC
                ADC     #$0f            ; Voice 3 control at D418
                sta     crs_d40f+1      ; timing issue requieres runtime mod of upcodes.
                sta     crs_d40f_1+1      ; timing issue requieres runtime mod of upcodes.
                lda     sptr_zp
                CLC
                ADC     #$1b            ; Voice 3 control at D418
                sta     crs_d41b+1      ; timing issue requieres runtime mod of upcodes.
                sta     crs_d41b_1+1      ; timing issue requieres runtime mod of upcodes.
                sta     crs_d41b_2+1      ; timing issue requieres runtime mod of upcodes.
                sta     crs_d41b_3+1      ; timing issue requieres runtime mod of upcodes.
                sta     crs_d41b_4+1      ; timing issue requieres runtime mod of upcodes.
                
; -- hack --
                lda #$48        ; test bit should be set
crs_d412        sta $d412
crs_d40f        sta $d40f
                lsr             ; activate sawtooth waveform
crs_d412_1      sta $d412
crs_d41b        lda $d41b
                tax             ; a to x 
                and #$fe        ; hvorfor ; 00 eller 01 giver 00
                bne unknownSid  ; unknown SID chip, most likely emulated or no SID in socket
crs_d41b_1      lda $d41b       ; try to read another time where the value should always be $03 on a real SID for all SID models
                cmp #$03        ; 6581 = 03 og 8580 = 03
                bne unknownSid
crs_d41b_2      lda $d41b       ; try to read another time where the value always be $03 on a real SID for all SID models
                cmp #$07        ; 6581 = 06 og 8580 = 05
                bcs unknownSid
crs_d41b_3      lda $d41b       ; try to read another time where the value always be $03 on a real SID for all SID models
                cmp #$08        ; 6581 = 08 og 8580 = 08
                beq loop2       ; så gå til loop2
unknownSid:
                ldx #$F0
loop2:
                txa    
                sta data1   
                cmp #$00  ; 
                beq sid8580 ; 
                cmp #$01  ; 
                beq sid6581 ; 
                jmp unknown ; 
sid8580:        
                LDA #$02
                STA data1
                jmp stoprealsid
sid6581:         
                LDA #$01
                STA data1
                jmp stoprealsid
unknown         
                LDA #$F0
                STA data1

stoprealsid            
                lda #$00
crs_d412_2      sta $D412
crs_d40f_1      sta $d40f
crs_d41b_4      lda $d41b
    

                ldx     x_zp            ; $ad 
                ldy     y_zp            ; $ae
                pla                     ; 
                rts 

                
;-------------------------------------------------------------------------
checksecondsid:
; the idea is to set $d41b to generate random numbers, and check which of the other mirrored regs 
;(add $20) is getting only 0 by peeking it a couple of times: that's the address of an additional sid.
; https://csdb.dk/forums/?roomid=11&topicid=114511
; if the second SID is differenct from D400 typer then base must be SECOND sid memory address and not D400.
; find last entry ind sid_list by using num_sids


                stx     x_zp            ; $ad 
                sty     y_zp            ; $ae
                pha                     ; 
                
                lda #$f0
                sta data1
css_begin                
                ; High byte
                lda     sptr_zp+1
                sta     css_d412_5+2      ; timing issue requieres runtime mod of upcodes.
                sta     css_d40f_5+2      ; timing issue requieres runtime mod of upcodes.
                sta     css_d412+2      ; timing issue requieres runtime mod of upcodes.
                sta     css_d40f+2      ; timing issue requieres runtime mod of upcodes.

                lda     mptr_zp+1
                sta     css_d41b+2      ; timing issue requieres runtime mod of upcodes.
                sta     css_d41b_5+2      ; timing issue requieres runtime mod of upcodes.
                ; low byte
                lda     sptr_zp
                CLC
                ADC     #$12            ; Voice 3 control at D418
                sta     css_d412_5+1      ; timing issue requieres runtime mod of upcodes.
                sta     css_d412+1      ; timing issue requieres runtime mod of upcodes.

                lda     mptr_zp
                CLC
                ADC     #$1b            ; Voice 3 control at D41B
                sta     css_d41b+1      ; timing issue requieres runtime mod of upcodes.
                sta     css_d41b_5+1      ; timing issue requieres runtime mod of upcodes.

                lda     sptr_zp
                CLC
                ADC     #$0f            ; Voice 3 control at D40F
                sta     css_d40f+1      ; timing issue requieres runtime mod of upcodes.
                sta     css_d40f_5+1      ; timing issue requieres runtime mod of upcodes.
                
; -- hack --
css_hack1:
                lda #$81        ; activate noise waveform
css_d412        sta $d412
                lda #$FF        ; 
css_d40f        sta $d40f
                ldx #$00
css_d41b        lda $d41b

                cmp #$00        ; Hvis 0, så er sid fundet.
                bne stopsrealsid
                inx
                cpx #10 ; if random gets 0 for some times it means it's not a mirror of d41b
                bne css_d41b
cssfound:       
                ldx mptr_zp+1
                ldy mptr_zp
                lda #$10
                sta data1
;; debug                
;                lda mptr_zp+1
;                jsr PRBYTE
;                lda mptr_zp
;                jsr PRBYTE
;                lda data1
;                jsr PRBYTE
;debugm1:
;       jsr readkeyboard
;       beq debugm1
;                

stopsrealsid            
                lda #$00
css_d412_5      sta $D412
css_d40f_5      sta $d40f
css_d41b_5      lda $d41b
    

                ldx     x_zp            ; $ad 
                ldy     y_zp            ; $ae
                pla                     ; 
                rts 

;-------------------------------------------------------------------------
     
DETECTSIDFX:

    ;Even though the SIDFX registers are hidden the D41E and D41F registers still receive
    ;  all writes and the SIDFX state machine will react to them, but they won't cause any
    ;  harm without the correct unlock sequence. But if there has been any random/unauthorized
    ;  writes since last reset (or last SCI command) then the internal state machine may be
    ;  in an unknown state. A sequence of SCISYN commands will eventually bring it back into
    ;  idle state where it can receive new commands. At least 8 SCISYN commands are required
    ;  but 16 are recommended in order to ensure compatibility with future firmware releases
    ;  (when using a loop the number of iterations doesn't usually matter).

    ldy #$0f
dloop2   jsr SCISYN    ;bring SIDFX SCI state machine into a known state
    dey
    bpl dloop2

    lda #$80    ;PNP hardware detection
    jsr SCIPUT
    lda #$50
    jsr SCIPUT    ;send login "PNP"
    lda #$4e
    jsr SCIPUT
    lda #$50
    jsr SCIPUT

    jsr SCIGET    ;Read vendor ID LSB
    sta PNP+0
    jsr SCIGET    ;Read vendor ID MSB
    sta PNP+1
    jsr SCIGET    ;Read product ID LSB
    sta PNP+2
    jsr SCIGET    ;Read product ID MSB
    sta PNP+3

    lda #$45    ;check device ID string
    cmp PNP+0
    bne NOSIDFX
    lda #$4c
    cmp PNP+1
    bne NOSIDFX
    lda #$12
    cmp PNP+2
    bne NOSIDFX
    lda #$58
    cmp PNP+3
    beq SIDFXFOUND

NOSIDFX:

    ;optionally warn user that SIDFX was not detected
    LDA #$31
    STA data1
    STA data2
    jmp PLAYTUNE

SIDFXFOUND:
    LDA #$30
    STA data1
    STA data2
    jsr REGUNHIDE   ;unhide register map

;    hvad skal der ske efter detect?
    
;    lda $d41d   ;Get SW1 position
;    lsr
;    lsr
;    lsr
;    lsr
;    and #$03
    ;your code
    ;optionally warn user if SW1 is not in center position (manually overriden)

;    lda $d41d   ;Get operating mode
;    and #$07
    ;your code

;    lda $d41d   ;Get stereo capability (are all grabbers installed?)
;    and #$08
    ;your code

    lda $d41e   ;Get SID1 model
    and #$03
    ;your code
;    jsr PRBYTE ; 03 = UNKN

    lda $d41e   ;Get SID2 model
    lsr
    lsr
    and #$03
    ;your code
;    jsr PRBYTE ; 01 = 6581, 02 = 8580, 03 = UNKN 

    lda $d41e   ;Get SID models
    and #$0f
    sta $d41e
    tax
;    jsr PRBYTE ; 07 = 
    
;    lda MODE6581,x    ;get mode for 6581 playback
    ;or
;    lda MODE8580,x    ;get mode for 8580 playback
  
;    lda MODE8580,x    ;get mode for 8580 playback
;    bne dloop3

    ;optionally warn user that the requested SID type is not available
;dloop3   
;    and #$07
;    ora #$f0
;    sta $d41d   ;Set playback mode
;    sta $d41d
    ;It is recommended to hide the control registers before initialization and playback of SID tunes
    ;  because unauthorized writes to the D41D-D41F area may cause unexpected behavior.
    ;But if only used with a SID player that never accesses these addresses there is of course no issues.
    jsr REGHIDE   ;hide register map
    
PLAYTUNE:
    jsr REGHIDE   ;hide register map
    ;play SID tune

    jsr loop1sek
    jsr loop1sek
    jsr loop1sek
    jsr loop1sek
    rts 
    
;-------------------------------------------------------------------------
; check pal/ntsc
;-------------------------------------------------------------------------

checkpalntsc:
              jsr palntsc                 ; perform check
              sta $02a6                   ; update KERNAL-variable
              rts
palntsc:
              sei                         ; disable interrupts
              ldx nmivec
              ldy nmivec+1                ; remember old NMI-vector
              lda #<rti2
              sta nmivec
              lda #>rti2                ; let NMI-vector point to
              sta nmivec+1                ; a RTI
wait:
              lda $d012
              bne wait                    ; wait for rasterline 0 or 256
              lda #$37
              sta $d012
              lda #$9b                    ; write testline $137 to the
              sta $d011                   ; latch-register
              lda #$01
              sta $d019                   ; clear IMR-Bit 0
wait1:
              lda $d011                   ; Is rasterbeam in the area
              bpl wait1                   ; 0-255? if yes, wait
wait2:
              lda $d011                   ; Is rasterbeam in the area
              bmi wait2                   ; 256 to end? if yes, wait
              lda $d019                   ; read IMR
              and #$01                    ; mask Bit 0
              sta $d019                   ; clear IMR-Bit 0
              stx nmivec
              sty nmivec+1                ; restore old NMI-vector
              cli                         ; enable interrupts
              rts                         ; return

rti2:         rti                         ; go immediately back after
                                          ; a NMI    


;-------------------------------------------------------------------------
;  Subroutine to print a byte in A in hex form (destructive)
;-------------------------------------------------------------------------

PRBYTE          PHA                     ;Save A for LSD
                stx  x_zp            ; $ad 
                sty  y_zp            ; $ad 
                LDA #35                  ; print #  
                jsr $ffd2
                PLA
                PHA
                LSR                     ;logic shift right -
                LSR
                LSR                     ;MSD to LSD position
                LSR
                JSR     PRHEX           ;Output hex digit
                ldx  x_zp            ; $ad 
                ldy  y_zp            ; $ad 
                PLA                     ;Restore A

; Fall through to print hex routine

;-------------------------------------------------------------------------
;  Subroutine to print a hexadecimal digit
;-------------------------------------------------------------------------

PRHEX           AND     #%00001111     ;Mask LSD for hex print
                ORA     #"0"            ;Add "0"
                CMP     #"9"+1          ;Is it a decimal digit?
                BCC     echo            ;Yes! output it
                ADC     #6              ;Add offset for letter A-F

echo            jsr $ffd2
                rts
                
;--------------------------------------------------------------------------------------------------
; Unhide SIDFX control registers
;
; A,X modified
;--------------------------------------------------------------------------------------------------

REGUNHIDE:
    lda #$c0    ;unhide register map
    jsr SCIPUT
    lda #$45
    jsr SCIPUT
    
    jsr SCISYN    ;wait for registers to become ready
    rts

;--------------------------------------------------------------------------------------------------
; Hide SIDFX control registers
;
; A,X modified
;--------------------------------------------------------------------------------------------------

REGHIDE:
    lda #$c1    ;hide register map
    jsr SCIPUT
    lda #$44
    jsr SCIPUT

    jsr SCISYN    ;wait for registers to become hidden
    rts

;--------------------------------------------------------------------------------------------------
; Exchange SCI (Serial Comminication Interface) byte
;
; A must contain the byte to send
; A will contain the byte received
; X modified
;--------------------------------------------------------------------------------------------------

SCIGET:
SCISYN:
    ldx #$0f    ;delay
loop4   dex
    bpl loop4
    lda #$00    ;"nop" SCI command
SCIPUT:
    ldx #$07    ;transfer 8 bits (MSB first)
    stx $d41e   ;bring SCI sync signal low
loop5   pha     ;save data byte
    sta $d41f   ;transmit bit 7
    lda $d41f   ;receive bit 0
    ror     ;push bit 0 to carry flag
    pla     ;restore data byte
    rol     ;shift transmitted bit out and received bit in
    dex     ;next bit
    bpl loop5      ;done?
    stx $d41e   ;bring SCI sync signal high
    rts
    
;--------------------------------------------------------------------------------------------------                
; init map
; while 96
; D400, D500, D600, D700, DE00, DF00
; 00,20,40,60,80,A0,C0,E0 ($20)
; sidlist, high
; sidlist, low
; sidlist, type (00,01,02,03,04,05,06,07,08)
; sptr_zp+1 = high
; sptr_zp = low
; hvis c128, så brug tab2. (D5, D6, DF)

tab2  !byte $D4,$D7,$DE,$DE
tab1  !byte $D4,$D5,$D6,$D7,$DE,$DF,$DF



sidstereostart:
        lda #$F0
        sta data1
        sta data2
        lda #$00
;        sta sidnum_zp ; 
        sta sptr_zp   ; store lowbyte   00 
        lda #$d4      ; load highbyte D4  (Sidhome)
        sta sptr_zp+1 ; store highbyte D4 (Sidhome)
        ldx #00       ; 
        stx scnt_zp   ; counter fra 0 til 48.
        ldy #01 ; must be 1
        sty mcnt_zp   ; y index til tab1
s_s_l1:
        lda #$F0
        sta data1
        sta data2
       
       lda sidtype
       cmp #$05 ; armsid
       bne s_s_FPGAsid 
       jsr Checkarmsid
       jmp s_s_ff  
s_s_FPGAsid:
       lda sidtype
       cmp #$06 ; FPGASid
       bne s_s_6581 
;       jsr checkfpgasid
       jmp s_s_ff  
s_s_6581:
       lda sidtype
       cmp #$01 ; 6581
       bne s_s_nosound 
       jsr checkrealsid
       jmp s_s_ff  
;debug
       ;lda sptr_zp+1
       ;jsr PRBYTE
       ;lda sptr_zp
       ;jsr PRBYTE
       ;lda data1
       ;jsr PRBYTE
s_s_nosound:
       jmp s_s_l3

;* Scan for and mark mirrors
; The problem is that the SID replicate the values of registers (00..1F) on the highbyte.
; D500, D520, D540, D560..D5F0 will show the same value even though the chip select address is D500.
; 
; find d400
; find second sid from d420 to d7e0 (fiktiv)
; check de00 to df00
;
s_s_ff  

       lda data1
       cmp #$10   ; hvis >10 next
       bcs s_s_next  
       ;;; found sid ;;;
       ;;; found sid ;;;
       ;;; found sid ;;;
       ldx sidnum_zp ; 
       inx 
       stx sidnum_zp
       ; load sid_list
       lda data1 
       sta sid_list_t,x
       lda sptr_zp
       sta sid_list_l,x
       lda sptr_zp+1
       sta sid_list_h,x
       ; load sid_list
       
       ; fiktiv loop 
       lda sptr_zp
       sta mptr_zp
       ldy sptr_zp+1
       sty mptr_zp+1
       ldx mcnt_zp
       stx cnt1_zp
       ldx scnt_zp
       stx cnt2_zp
; hvorfor #$DE????????? har samme mirror af værdier som d500,d600, ; i stedet for anothersid brug 6581/8580.
       cpy #$DE ; hvis y>=#$DE 
       bcs s_s_next ; hvis #$DE så skip
;--
       lda sidtype 
       cmp #$05       ;ARMSID / SwinsidU
       bne s_s_lfpgasid 
       ; hvis scnt_zp > D400 så ingen grund til checkanothersid. max 2 sids? måske 4 fpgasid?
       jsr checkanothersid      
;       jmp s_s_E000
;       jmp s_s_next
       jsr s_s_l3
s_s_lfpgasid:
       lda sidtype 
       cmp #$06       ;FPGAsid
       bne s_s_lfpgasid_2 
;       jsr checkanothersid      
       jsr fiktivloop ; find second sid max DFFF
;       jsr checksecondFPGA
       jsr s_s_l3
s_s_lfpgasid_2:
       lda sidtype 
       cmp #$07       ;FPGAsid
       bne s_s_l6581 
;       jsr checkanothersid      
       jsr fiktivloop ; find second sid max DFFF
;       jsr checksecondFPGA
       jsr s_s_l3
s_s_l6581:
       ; brug kun fiktivloop hvis D400 er 8580, 6581
       lda sidtype 
       cmp #$01
       bne s_s_next
       ; set values
       jsr fiktivloop ; find second sid max DFFF
       jsr s_s_l3
       
s_s_E000:
       ; sæt DE00
       ; check for FCIII
;       lda #$00
       lda #$E0
       sta sptr_zp 
;       lda #$DE
       lda #$DF
       sta sptr_zp+1 
       lda $20
       sta scnt_zp    ; max count
       ldy #$05       ; set DE00 i tab1
       sty mcnt_zp    ;
       
       
       ; sid map giver mening.... undgå at printe undervejs, men vent til sidst.
       ; high, low, type, 
s_s_next       
       lda sptr_zp
       cmp #$E0 ; hvis E0, y++
       bne s_s_l2
       ; get D4 from tab1
       ldy mcnt_zp
       lda tab1,y
       sta sptr_zp+1
       iny
       sty mcnt_zp
s_s_l2       
       ; add #$20
       lda sptr_zp
       clc ; clear cary
       adc #$20
       sta sptr_zp
       ldx scnt_zp
       inx
       stx scnt_zp
       cpx #$30
       beq s_s_l3
       jmp s_s_l1 
;--------------------------
s_s_l3
       rts   
;--------------------------------------------------------------------------------------------------                
; cnt1_zp
; mptr_zp
fiktivloop:
;* Scan for and mark mirrors
; The problem is that the SID mirrors the values of registers (00..1F) on the highbyte.
; D500, D520, D540, D560..D7F0 will show the same value even though the chip select address is D500.
; the idea is to set $d41b to generate random numbers, and check which of the other mirrored regs 
;(add $20) is getting only 0 by peeking it a couple of times: that's the address of an additional sid.
; https://csdb.dk/forums/?roomid=11&topicid=114511
; DE00 and DF00 also mirror values

; set values
; D400
       lda #$D4
       lda sptr_zp+1
       sta mptr_zp+1
       lda #$00
       lda sptr_zp
       sta mptr_zp
f_l_l1:
;       jsr checkfpgasid
;       lda data1
;       cmp $07
;       bne f_l_l_fpga1
;       jmp f_l_l_found
;f_l_l_fpga1
;       lda data1
;       cmp $06
;       bne f_l_l_sec
;       jmp f_l_l_found
f_l_l_sec
       jsr checksecondsid
       lda data1
       cmp #$10
       BNE f_l_next

f_l_l_found
       ;hvis fundet
       ; sanity check
       lda sidnum_zp
       cmp #$08
       bcS f_l_next; hvis x >=09 then slut     
       ; sanity check
       ;;; found sid ;;;
       ldx sidnum_zp ; 
       inx 
       stx sidnum_zp
       lda mptr_zp+1
       sta sptr_zp+1
       lda mptr_zp
       sta sptr_zp
       ; load sid_list
       lda data1 
       sta sid_list_t,x
       lda sptr_zp
       sta sid_list_l,x
       lda sptr_zp+1
       sta sid_list_h,x
       ; load sid_list
       ; choose next sid found as base
       lda sptr_zp+1
       lda sptr_zp
       
       
f_l_next       
       lda mptr_zp
       cmp #$E0 ; hvis E0, y++
       bne f_l_l2
       ; get D4 from tab1
       ldy cnt1_zp 
       ; if c128 then lda tab2,y
       lda za7
       cmp #$FF 
       bne f_l_l3
       lda tab1,y
       jmp f_l_l4
f_l_l3       
       lda tab2,y ; c128
f_l_l4       
       sta mptr_zp+1
       iny
       sty cnt1_zp 
f_l_l2       
       ; add #$20 
       lda mptr_zp
       clc ; clear cary
       adc #$20
       sta mptr_zp
       ldy mptr_zp+1
       ldx cnt2_zp
       inx
       stx cnt2_zp
       cpx #$30       ; ikke $30
       bcc f_l_l1        
       rts
;--------------------------------------------------------------------------------------------------                
checkanothersid:
; FPGAsid and ARMsid/Swinsid Ultimate
; the idea is to set $d41b to generate random numbers, and check which of the other mirrored regs 
;(add $20) is getting only 0 by peeking it a couple of times: that's the address of an additional sid.
; https://csdb.dk/forums/?roomid=11&topicid=114511


                stx     x_zp            ; $ad 
                sty     y_zp            ; $ae
                pha                     ; 
                
                lda #$f0
                sta data1
                
ccas_begin                
;                lda     mptr_zp+1
;                lda     mptr_zp
                
;                ADC     #$1b            ; Voice 3 control at D41B
;                sta     ccas_d41b+1      ; timing issue requieres runtime mod of upcodes.
;                lda     mptr_zp
                
; -- hack --
ccas_hack1:
                lda #$81        ; activate noise waveform
                sta $d412
                lda #$FF        ; 
                sta $d40f
                ldx #$d4        ; set x = $D400
                stx za8+1
                ldx #$00
                stx za8         ; set x = $D400 
                
ccas_d41b        ;lda $d41b
                ldy #$1b
                lda (za8),y  ; lda D41B 
                cmp #$00        ; Hvis 0, så er sid fundet.
                bne ccas_loop
                inx
                cpx #10 ; if random gets 0 for some times it means it's not a mirror of d41b
                bne ccas_d41b
                jmp ccasfound
                
ccas_loop       lda za8
                clc
                adc #$20
                sta za8       ; zfb+$20
                bne ccas_noinczfc  ; forskellige fra 0
                inc za8+1
                lda za8+1
                cmp #$d8      ; 
                bcs ccasstopsrealsid  ; hvis >= $D800 så finished
ccas_noinczfc
                jmp ccas_d41b ; en tur til
                
ccasfound:      
                lda #$10
                sta data1
                lda     za8
                sta     sptr_zp         ; store lowbyte 00 (Sidhome)
                lda     za8+1            ; load highbyte D4  (Sidhome)
                sta     sptr_zp+1       ; store highbyte D4 (Sidhome)
                jsr Checkarmsid     
                lda data1
                cmp #04 ; S
                bne ccas_armsid
                ; swinddectect
                jmp ccas_writesidl 
ccas_armsid:
                lda data1
                cmp #05 ; N
                bne ccas_fpgasid
                jmp ccas_writesidl 
                ; armsid 
ccas_fpgasid:
                lda #$10
                sta data1
                lda     za8
                sta     sptr_zp         ; store lowbyte 00 (Sidhome)
                lda     za8+1            ; load highbyte D4  (Sidhome)
                sta     sptr_zp+1       ; store highbyte D4 (Sidhome)
;debug
                ;lda     za8+1            ; load highbyte D4  (Sidhome)
                ;jsr PRBYTE
                ;lda     za8
                ;jsr PRBYTE
                ;
                jsr checkfpgasid
; debug
;                lda data1
;                jsr PRBYTE
                
                lda data1
                cmp #06 ; N
                bne ccas_fpgasid2
                jmp ccas_writesidl 
ccas_fpgasid2:
                lda data1
                cmp #07 ; N
                bne ccasstopsrealsid
;-----                
ccas_writesidl
                ldx sidnum_zp ; 
                inx 
                stx sidnum_zp
                lda data1 
                sta sid_list_t,x
                lda sptr_zp
                sta sid_list_l,x
                lda sptr_zp+1
                sta sid_list_h,x
                ; load sid_list

;debug
       ;lda sptr_zp+1
       ;jsr PRBYTE
       ;lda sptr_zp
       ;jsr PRBYTE
       ;lda data1
       ;jsr PRBYTE


                
ccasstopsrealsid            

                ldx     x_zp            ; $ad 
                ldy     y_zp            ; $ae
                pla                     ; 
                rts 


;--------------------------------------------------------------------------------------------------                
checksecondFPGA
;* Scan for and mark mirrors
; The problem is that the SID mirrors the values of registers (00..1F) on the highbyte.
; D500, D520, D540, D560..D7F0 will show the same value even though the chip select address is D500.
; the idea is to set $d41b to generate random numbers, and check which of the other mirrored regs 
;(add $20) is getting only 0 by peeking it a couple of times: that's the address of an additional sid.
; https://csdb.dk/forums/?roomid=11&topicid=114511
; DE00 and DF00 also mirror values

; set values
; D400
       lda #$D4
       lda sptr_zp+1
       sta mptr_zp+1
       lda #$00
       lda sptr_zp
       sta mptr_zp
csfp_l_l1:
       jsr checkfpgasid
       lda data1
       cmp $07
       bne csfp_l_l_fpga1
       jmp csfp_l_l_found
csfp_l_l_fpga1
       lda data1
       cmp $06
       bne csfp_l_l_sec
       jmp csfp_l_l_found
csfp_l_l_sec
;       jsr checksecondsid
;       lda data1
;       cmp #$10
;       BNE csfp_l_next
        jmp csfp_l_next

csfp_l_l_found
       ;hvis fundet
       ; sanity check
       lda sidnum_zp
       cmp #$08
       bcS csfp_l_next; hvis x >=09 then slut     
       ; sanity check
       ;;; found sid ;;;
       ldx sidnum_zp ; 
       inx 
       stx sidnum_zp
       lda mptr_zp+1
       sta sptr_zp+1
       lda mptr_zp
       sta sptr_zp
       ; load sid_list
       lda data1 
       sta sid_list_t,x
       lda sptr_zp
       sta sid_list_l,x
       lda sptr_zp+1
       sta sid_list_h,x
       ; load sid_list
       ; choose next sid found as base
       lda sptr_zp+1
       lda sptr_zp
       
       
csfp_l_next       
       lda mptr_zp
       cmp #$E0 ; hvis E0, y++
       bne csfp_l_l2
       ; get D4 from tab1
       ldy cnt1_zp 
       ; if c128 then lda tab2,y
       lda za7
       cmp #$FF 
       bne csfp_l_l3
       lda tab1,y
       jmp csfp_l_l4
csfp_l_l3       
       lda tab2,y ; c128
csfp_l_l4       
       sta mptr_zp+1
       iny
       sty cnt1_zp 
csfp_l_l2       
       ; add #$20 
       lda mptr_zp
       clc ; clear cary
       adc #$20
       sta mptr_zp
       ldy mptr_zp+1
       ldx cnt2_zp
       inx
       stx cnt2_zp
       cpx #$30       ; ikke $30
       bcc csfp_l_l1        
       rts
                
;--------------------------------------------------------------------------------------------------                
sidstereo_print:

; check FPGA, SWIN, ARMSID  
;swinsidUf      !text "SWINSID ULTIMATE FOUND"   ,0  ; data1=$04 data2=$57
;armsidf        !text "ARMSID FOUND" ,0              ; data1=$05 data2=$4f
;nosoundf       !text "NOSID FOUND" ,0               ; data1=$f0 data2=$f0
;fpgasidf_8580u !text "FPGASID 8580 FOUND"   ,0      ; data1=$06 data2=$3f
;fpgasidf_6581u !text "FPGASID 6581 FOUND"   ,0      ; data1=$07 data2=$00
;l6581f         !text "6581 FOUND"   ,0             ; data1=$02 data2=$02
;l8580f         !text "8580 FOUND" ,0               ; data1=$01 data2=$01
;swinsidnanof   !text "SWINSID NANO FOUND" ,0        ; data1=$10 data2=$10

;        lda sidnum_zp
;        jsr PRBYTE
        
        lda sidnum_zp
        bne ssp_init 
        jmp ssp_ex1
ssp_init:
        ldy #$00
        sty tmp2_zp; counter antal sid.
ssp_loop:
        ldy tmp2_zp
        iny
        sty tmp2_zp
        LDA #13   ; row
        CLC
        ADC tmp2_zp
        TAX    
        LDY #13    ; Select column 
        JSR $E50C   ; Set cursor 
;        lda sptr_zp+1
        ldy tmp2_zp
        lda sid_list_h,y
        ; sanity
        bne ssp_loop2 ; hvis $00 i high, så stop     
        jmp ssp_skp20
        ; sanity
ssp_loop2:        
        lda sid_list_h,y
        jsr     print_hex
;        lda sptr_zp
        lda sid_list_l,y
        jsr     print_hex
        lda     #$20        ; space
        jsr     $ffd2
;        lda     data1
        lda sid_list_t,y  ; type
        cmp     #$02
        bne     ssp_skp4
        lda     #<l8580f
        ldy     #>l8580f
        jsr     $ab1e
        jmp     ssp_skp20
ssp_skp4:
        cmp     #$01
        bne     ssp_skp5
        lda     #<l6581f
        ldy     #>l6581f
        jsr     $ab1e
        jmp     ssp_skp20
ssp_skp5:
        cmp     #$04
        bne     ssp_skp6
        lda     #<swinsidUf
        ldy     #>swinsidUf
        jsr     $ab1e
        jmp     ssp_skp20
ssp_skp6:
        cmp     #$05
        bne     ssp_skp7
        ldx     data3
        cpx     #$53
        bne     ssp_skp7
        ; check for ; data3=$53
        lda     #<arm2sidf
        ldy     #>arm2sidf
        jsr     $ab1e
        jmp     ssp_skp20
ssp_skp7:
        cmp     #$05 
        bne     ssp_skp8
        lda     #<armsidf
        ldy     #>armsidf
        jsr     $ab1e
        jmp     ssp_skp20
ssp_skp8:
        cmp     #$06
        bne     ssp_skp9
        lda     #<fpgasidf_8580u
        ldy     #>fpgasidf_8580u
        jsr     $ab1e
        jmp     ssp_skp20
ssp_skp9:
        cmp     #$07
        bne     ssp_skp10
        lda     #<fpgasidf_6581u
        ldy     #>fpgasidf_6581u
        jsr     $ab1e
        jmp     ssp_skp20
ssp_skp10:
        cmp     #$10
        bne     ssp_skp20
        lda     #<secondsid
        ldy     #>secondsid
        jsr     $ab1e
        jmp     ssp_skp20
ssp_skp11:
        cmp     #$08
        bne     ssp_skp20
        lda     #<swinsidnanof
        ldy     #>swinsidnanof
        jsr     $ab1e
        jmp     ssp_skp20
        
ssp_skp20:

;debugl:
;       jsr readkeyboard
;       beq debugl
;        
        lda     #13
        jsr     $ffd2
        ldy tmp2_zp
        cpy sidnum_zp
        beq ssp_ex1
        jmp ssp_loop
ssp_ex1:
        rts
       
;--------------------------------------------------------------------------------------------------                
; siddetectstart


;**************************************************************************
loop1sek:
                stx  x_zp            ; $ad 
                sty  y_zp            ; $ad 
                pha
                ldx sptr_zp 
                ldy sptr_zp+1 
                ldx #$FF
loop1sekx       dex       ; x--
                nop
                nop
                nop
                nop
                bne loop1sekx ; gentag for at blive klar.
                ldx     x_zp            ; $ad 
                ldy     y_zp            ; $ad 
                pla
                rts
                
;**************************************************************************
;* NAME  print_hex
print_hex:
        pha
        lsr
        lsr
        lsr
        lsr
        jsr     ph_skp1
        pla
        and     #$0f
ph_skp1:
        cmp     #$0a
        bcc     ph_skp2
; C = 1
;        adc     #"A"-$0a-"0"-1
        adc     #6
ph_skp2:
; C = 0
        adc     #"0"
        jmp     $ffd2
       rts
;----------------------------------------------------------------------------------------
;http://www.baltissen.org/newhtm/d700.htm
;https://csdb.dk/forums/?roomid=14&topicid=99181&showallposts=1
;you know the VIC-II video chip occupies the $D000/D3FF area in both the C64 and C128. 
;But while the SID sound occupies $D400/D7FF in the C64, in the C128 it only occupies the area $D400/D4FF. 
;$D5xx is occupied by the MMU, $D6xx by the VDC, the second video chip and $D7xx is free. 
;This free $D7xx area is often used for installing a second SID sound chip in the C128. 
;Something where quite some C64 owners were jealous of
; write $00 to $D030 and then read it back, AFAIK you'll then always get $FF on C64 and $FC on C128.
; TC64 looks like C128, so return $FA
            
check128:
      LDA #$00
      sta $D030
      lda $d030
      cmp #$FF
      BEQ check128_c64
      cmp #$FC
      BEQ check128_c128
      jmp check128_unknown
check128_c64
      sta za7
      jmp check128_end 
check128_c128
      lda $D0FE
;      JSR PRBYTE
      lda #$2A
      sta $D0FE
      lda $D0FE
      sta za7
      sta za7
      jmp check128_end 
check128_unknown
      sta za7
check128_end 
      rts
;--------------------------------      
; new swinsidMicrocheck ; 8580 = 01, 6581=01, ARM=0, SwinsidNano=99 NOSID=99 ; maybe check for 
;--------------------------------      

checkswinmicro:      
    LDX #$1F ;00
    LDA #$00
checkswinloop1:    
    STA $D400,X
    DEX
    BNE checkswinloop1
    LDA #$00
    STA $D413 ; AD
    lda #$F0
    STA $D414 ; SR
    lda #$41  ; gate bit set, noise set
    sta $D412 ; control register
    sta $D40e ; Voice 3 Frequency Control (low byte)
    sta $D40f ; Voice 3 Frequency Control (hogn byte)
    lda $D41c ;
;    lda #$01
    cmp #$01
    beq checkswinloop2
    ; found micro sid
    stx $d412
    lda #$08
    sta data1
    sta data2
    jmp checkswinend
checkswinloop2:
    lda #$f0
    sta data1
    sta data2
checkswinend:
    rts
      
      
;====================== 
;COLOUR WASHING ROUTINE 
;====================== 
COLWASH              LDA COLOUR+$00 
                     STA COLOUR+$28 
                     LDX #$00 
CYCLE                LDA COLOUR+$01,X 
                     STA COLOUR+$00,X 
                     LDA COLOUR,X 
;                     STA $Dbc0,X ; last line 
                     STA $D800,X ; last line 
                     INX 
                     CPX #$28 
                     BNE CYCLE 
                     RTS

;**************************************************************************
; Funny sid check Decay
;-------------------------------------------------------------------------------
calcandloop:
    ldx NumberInts; set til NumberInts
calcand_bigloop
    stx ZPbigloop; flyt x til zpbigloop
    txs         ; flyt x til stack
    jsr calc_start
    tsx         ; hent x fra stack
    dex
    bne calcand_bigloop ; or directly: beq frodo
    ; calc
    LDx #1
calcand_calcloop    
    stx ZPArrayPtr
    txs         ; flyt a til stack
    jsr ArithmeticMean;
    tsx         ; hent a fra stack
    inx 
    cpx #4
    bne calcand_calcloop
    jmp funny_print
    rts  

;----------------
; start test
    
calc_start:
    lda #0
    sta $0400
    sta $0401
    sta $0402

    sei
    lda #$1f
    sta $d418 ; gem 31 i $d418
calc_loop
    inc $0400 ; VICSCN +1 til indholdet af 0400
    bne calc_nohi  ; 
    inc $0401 ;
    bne calc_nohi  ;
    inc $0402 ; VICSCN +1 til indholdet af 0402
    lda $0402 ; læs værdi af 0402
    cmp #$02  ; hvis 2 
    beq calc_check ; or directly: beq frodo
calc_nohi
    lda $d418 ; læs d418 
    bne calc_loop
calc_check
    lda $0400 ; læs 0400
    sta data1 ; gem d400  
    ldx ZPbigloop
    dex
    sta ArrayPtr1,x
    lda $0401 ; læs 0401
    sta data2 ; gem d401
    ldx ZPbigloop
    dex
    sta ArrayPtr2,x
    lda $0402 ; læs 0402
    sta data3 ; gem 0402  
    ldx ZPbigloop
    dex
    sta ArrayPtr3,x
    rts
    
;---------------------------------------------------------------------    
; new check
;---------------------------------------------------------------------    
checktypeandprint:

;    LDA #<slabel 
;    LDY #>slabel 
;    jsr $AB1E
        
    lda data3 ; 
    cmp #$02  ; hvis 2
    bne nc_Swinsidn
    jmp nc_unknown
    
; 01-02 00 00| Swinsid Nano                   | done
nc_Swinsidn
    lda data1
    cmp #$01
    bcc nc_ULTIsid     ; hvis data1 < cmp gå til nc_FastSid
    cmp #$03
    bcs nc_ULTIsid     ; hvis data1 >= cmp gå til nc_FastSid
    lda data2
    bne nc_ULTIsid
    ; found         
    LDA #<sunknown 
    LDY #>sunknown 
    jsr $AB1E
    jmp exit
; DA-F1 00 00| ULTIsid                        |    
nc_ULTIsid    
    lda data1
    cmp #$DA
    bcc nc_hoxs     ; hvis data1 < cmp gå til nc_FastSid
    cmp #$F2
    bcs nc_hoxs     ; hvis data1 >= cmp gå til nc_FastSid
    lda data2
    bne nc_hoxs
    ; found         
    LDA #<sULTIsid 
    LDY #>sULTIsid 
    jsr $AB1E
    jmp exit 
 ; 00 19-19 00| Hoxs                           |
nc_hoxs
    lda data2
    cmp #$19
    bne nc_Residfp6581d    
    lda data3
    bne nc_Residfp6581d
    ; found         
    LDA #<shoxs 
    LDY #>shoxs 
    jsr $AB1E
    jmp exit 

; 00 07-07 00| C64 Deb Vice 3.1 RESID-FP 6581 |
nc_Residfp6581d
    lda data2
    cmp #$07
    bne nc_Fast6581d     ; hvis data1 >= cmp gå til nc_FastSid
    lda data3
    bne nc_Fast6581d
    ; found         
    LDA #<sResidfp6581d 
    LDY #>sResidfp6581d 
    jsr $AB1E
    jmp exit 

; 05-05 00 00| C64 Deb Vice 3.1 fastSID 6581  |
nc_Fast6581d
    lda data1
    cmp #$05
    bne nc_Resid6581d     ; hvis data1 >= cmp gå til nc_FastSid
    lda data2
    bne nc_Resid6581d
    ; found         
    LDA #<sFast6581d 
    LDY #>sFast6581d 
    jsr $AB1E
    jmp exit 
; 00 03-03 00| C64 Deb Vice 3.1 RESID 6581    |
nc_Resid6581d
    lda data2
    cmp #$03
    bne nc_Swinsidu     ; hvis data1 >= cmp gå til nc_FastSid
    lda data3
    bne nc_Swinsidu
    ; found         
    LDA #<sResid6581d 
    LDY #>sResid6581d 
    jsr $AB1E
    jmp exit 
    
; 00 16-18 00| Swinsid Ultimate               | done
nc_Swinsidu
    lda data2
    cmp #$16
    bcc nc_FPGAsid     ; hvis data1 < cmp gå til nc_FastSid
    cmp #$19
    bcs nc_FPGAsid     ; hvis data1 >= cmp gå til nc_FastSid
    lda data3
    bne nc_FPGAsid
    ; found         
    LDA #<sSwinsidU 
    LDY #>sSwinsidU 
    jsr $AB1E
    jmp exit 
; 00 05-06 00| FPGAsid
nc_FPGAsid
    lda data2
    cmp #$05
    bcc nc_Resid8580     ; hvis data1 < $B4 gå til nc_FastSid
    cmp #$07
    bcs nc_Resid8580     ; hvis data1 >= $B9 gå til nc_FastSid
    lda data3
    bne nc_Resid8580
    ; found         
    LDA #<sFPGAsid 
    LDY #>sFPGAsid 
    jsr $AB1E
    jmp exit 
; 00 98-98 00| Vice 3.3 RESID fast/ 8580
nc_Resid8580 
    lda data2
    cmp #$98
    bne nc_Resid6581
    lda data3
    bne nc_Resid6581
    LDA #<sResid8580 
    LDY #>sResid8580
    jsr $AB1E 
    jmp exit 
; 00 01-01 00| Vice 3.3 RESID fast/ 6581
nc_Resid6581 
    lda data2
    cmp #$01
    bne nc_FastSid     ; hvis data1 < $B4 gå til nc_FastSid
    lda data3
    bne nc_FastSid
    ; found         
    LDA #<sResid6581 
    LDY #>sResid6581 
    jsr $AB1E 
    jmp exit 
; 02-05 00 00| Vice 3.3 FastSID 
nc_FastSid   
    lda data1
    cmp #$02
    bcc nc_nextsid     ; hvis data1 < $B4 gå til nc_FastSid
    cmp #$05
    bcs nc_nextsid     ; hvis data1 >= $B9 gå til nc_FastSid
    lda data2
    bne nc_nextsid
    ; found         
    LDA #<sFastSid 
    LDY #>sFastSid 
    jsr $AB1E
    jmp exit 
nc_nextsid   
    jmp exit 

nc_unknown:
    LDA #<sunknown 
    LDY #>sunknown 
    jsr $AB1E 
    lda data1
    jsr $FFD2
    lda data2
    jsr $FFD2
    lda data3
    jsr $FFD2
    
    
exit:    
   rts 
    
;-----------------------------------------------------------------------------------
; Calc average of max 255 8 bit values.
ArithmeticMean:
      PHA
      TYA
      PHA   ;push accumulator and Y register onto stack
 
 
      LDA #0
      STA Temp
      STA Temp+1  ;temporary 16-bit storage for total
 
      LDY NumberInts  
      BEQ Done  ;if NumberInts = 0 then return an average of zero
 
      DEY   ;start with NumberInts-1
AddLoop: 
      LDA ZPArrayPtr; hent 1,2,3
      CMP #1 
      beq ArrayPtr1l
      CMP #2 
      beq ArrayPtr2l
      CMP #3 
      beq ArrayPtr3l
      ; not needed
      LDA ArrayPtr2,Y ; 
      jmp CLCloop
ArrayPtr1l
      LDA ArrayPtr1,Y ; 
      jmp CLCloop
ArrayPtr2l
      LDA ArrayPtr2,Y ; 
      jmp CLCloop
ArrayPtr3l
      LDA ArrayPtr3,Y ; 
CLCloop
      CLC
      ADC Temp
      STA Temp
      LDA Temp+1
      ADC #0
      STA Temp+1
      DEY
      CPY #255
      BNE AddLoop
 
      LDY #-1
DivideLoop:   
      LDA Temp
      SEC
      SBC NumberInts
      STA Temp
      LDA Temp+1
      SBC #0
      STA Temp+1
      INY
      BCS DivideLoop
 
Done: 
      STY ArithMean ;store result here
      PLA   ;restore accumulator and Y register from stack
      TAY
      PLA
      RTS   ;return from routine


      
      
;-------------------------------------------------------------------------
;
;-------------------------------------------------------------------------
; DATA    
;-------------------------------------------------------------------------

swinsidUf      !text "SWINSID ULTIMATE FOUND"   ,0  ; data1=$04 data2=$04
armsidf        !text "ARMSID FOUND" ,0              ; data1=$05 data2=$4f
nosoundf       !text "NOSID FOUND" ,0               ; data1=$f0 data2=$f0
fpgasidf_8580u !text "FPGASID 8580 FOUND"   ,0      ; data1=$06 data2=$3f
fpgasidf_6581u !text "FPGASID 6581 FOUND"   ,0      ; data1=$07 data2=$00
l6581f         !text "6581 FOUND"   ,0             ; data1=$02 data2=$02
l8580f         !text "8580 FOUND" ,0               ; data1=$01 data2=$01
swinsidnanof   !text "SWINSID NANO FOUND" ,0        ; data1=$08 data2=$08
unknownsid      !text "UNKNOWN SID FOUND" ,0        ; data1=$09 data2=$09
secondsid      !text "ANOTHER SID FOUND" ,0        ; data1=$10 data2=$10
swinsidmicrof  !text "SWINSID MICRO FOUND",0        ; data1=$0a data2=$0a
ultisidf_8580u !text "ULTISID 8580 FOUND"   ,0      ; data1=$20 data2=$20
ultisidf_6581u !text "ULTISID 6581 FOUND"   ,0      ; data1=$21 data2=$21
sidfxu         !text "SIDFX FOUND"   ,0             ; data1=$30 data2=$30
nosidfxu       !text "NOSIDFX FOUND" ,0             ; data1=$31 data2=$31
pal_text       !text "PAL-MACHINE FOUND",0,0
ntsc_text      !text "NTSC-MACHINE FOUND",0,0
c64_text       !text " C64",0,0
c128_text      !text " C128",0,0
tc64_text      !text " TC64",0,0
arm2sidf       !text "ARM2SID FOUND" ,0              ; data1=$05 data2=$4f data3=$53


data1_old           !byte 10 
                !byte 0
data2_old           !byte 10 
                !byte 0
MODE6581:     !byte $f0,$f1,$f0,$f0,$f2,$f1,$f2,$f2,$f0,$f1,$f0,$f0,$f0,$f1,$f0,$f0
MODE8580:     !byte $f0,$f0,$f1,$f0,$f0,$f0,$f1,$f0,$f2,$f2,$f1,$f2,$f0,$f0,$f1,$f0
MODEUNKN:     !byte $f0,$f0,$f0,$f0,$f0,$f0,$f0,$f2,$f0,$f0,$f0,$f2,$f0,$f1,$f1,$f0



    ;D41E bits 3-0 (SID model) -> D41D bits 2-0 (playback mode)
    ;
    ;MODELS SID1  SID2  6581  8580
    ;
    ;0000 NONE  NONE  0 0
    ;0001 6581  NONE  1 0 <-- 01
    ;0010 8580  NONE  0 1
    ;0011 UNKN  NONE  0 0 <-- 03
    ;0100 NONE  6581  2 0
    ;0101 6581  6581  1 0
    ;0110 8580  6581  2 1
    ;0111 UNKN  6581  2 0 <-- 07
    ;1000 NONE  8580  0 2
    ;1001 6581  8580  1 2
    ;1010 8580  8580  0 1
    ;1011 UNKN  8580  0 2
    ;1100 NONE  UNKN  0 0
    ;1101 6581  UNKN  1 0
    ;1110 8580  UNKN  0 1
    ;1111 UNKN  UNKN  0 0
    ;
    ;Example tables, default mode (0) is selected when requested SID type is not available (recommended)

PNP:    !byte 4,0,0,0,0

screen:                
         ;0123456789012345678901234567890123456789
    !scr "            siddetector v1.10           " ;0
    !scr "                   by                   " ;1
    !scr "          funfun/triangle 3532          " ;2
    !scr "                                        " ;3
    !scr "armsid.....:                            " ;4
    !scr "swinsid....:                            " ;5
    !scr "fpgasid....:                            " ;6
    !scr "6581 sid...:                            " ;7
    !scr "8550 sid...:                            " ;8
    !scr "sidfx......:                            " ;9
    !scr "nosid......:                            " ;10
    !scr "$d418 decay:                            " ;11
    !scr "pal/ntsc...:                            " ;12
    !scr "tc64.......:                            " ;13
    !scr "stereo sid.:                            " ;14
    !scr "                                        " ;15
    !scr "                                        " ;16
    !scr "                                        " ;17
    !scr "                                        " ;18
    !scr "                                        " ;19
    !scr "                                        " ;20
    !scr "                                        " ;21
    !scr "unknown sid can be mister or nanosid or " ;22
    !scr "ultisid(u64). another sid is typical a  " ;23
    !scr "realsid (6581/8580), but can be other.  " ;24

;DATA TABLES FOR COLOURS

COLOUR       !BYTE $09,$09,$02,$02,$08 
             !BYTE $08,$0A,$0A,$0F,$0F 
             !BYTE $07,$07,$01,$01,$01 
             !BYTE $01,$01,$01,$01,$01 
             !BYTE $01,$01,$01,$01,$01 
             !BYTE $01,$01,$01,$07,$07 
             !BYTE $0F,$0F,$0A,$0A,$08 
             !BYTE $08,$02,$02,$09,$09 
             !BYTE $00,$00,$00,$00,$00    
* = $1D00         
num_sids:
        !byte    $0,$9,$9,$9,$9,$9,$9,$9
sid_list_l:
        !byte    $0,$0,$0,$0,$0,$0,$0,$0
sid_list_h:
        !byte    $0,$0,$0,$0,$0,$0,$0,$0
sid_list_t:
        !byte    $0,$0,$0,$0,$0,$0,$0,$0

sid_map:
        !byte    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0  ; D400, D500
        !byte    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0  ; D600, D700
        !byte    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0  ; 
        !byte    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0  ; 
        !byte    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0  ; 
        !byte    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0  ; DE00, DF00

; data

stringtable
shoxs         !text "HOXS64"   ,0
sreal6581     !text "REAL 6581",0
snosound      !text "NO SOUND" ,0
sfrodo        !text "FRODO"    ,0
sreal8580     !text "REAL 8580",0
sSwinsidn     !text "SWINSID NANO",0
sARMSID       !text "ARMSID",0 
sSwinsidU     !text "SWINSID ULTIMATE",0 
s6581R3       !text "6581 R3 2084",0
s6581R4AR     !text "6581 R4AR 5286",0
s6581R4       !text "6581 R4 1886",0
s6581R2       !text "6581 R2 5182",0
sFPGAsid      !text "FPGASID",0
sResid8580    !text "VICE3.3 RESID FS 8580",0
sResid6581    !text "VICE3.3 RESID FS 6581",0
sFastSid      !text "VICE3.3 FASTSID",0
sResid6581d   !text "C64DBG RESID 6581/8580",0
sFast6581d    !text "C64DBG FASTSID 6581/8580",0
sResidfp6581d !text "C64DBG RESIDFP 6581/8580",0
sYACE64       !text "YACE64",0
semu64        !text "EMU64",0
sULTIsid      !text "ULTISID",0
sULTIsidno    !text "U64 NOSID at $D400",0
sunknown      !text "UNKNOWNSID",0
slabel        !text "$D418 DECAY:",0
sblank        !text "     ",0

         
      
Temp:       !byte $00,$00
NumberInts  !byte $06 ; 6 loops
ArithMean:  !byte $00,$00
ArrayPtr:   !Byte $00 
ArrayPtr1:   !byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00 
ArrayPtr2:   !byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00 
ArrayPtr3:   !byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00

data4        !byte 0,0
         
; eof         
        
     