* = $0801
!byte $0C,$08,$06,$00,$9E,$20,$32,$30
!byte $36,$34,$00,$00,$00,$00,$00

label_0810
 A9 00      lda #$00
 8D 20 D0   sta $d020
 8D 21 D0   sta $d021
 20 01 0F   jsr label_0f01
 93 00      ahx $2000, x

label_081d
 20 60 09   jsr label_0960

label_0820
 20 E4 FF   jsr $ffe4
 F0 FB      beq label_0820
 8D 00 C0   sta $c000
 C9 86      cmp #$86
 D0 06      bne label_0832
 20 B3 0C   jsr label_0cb3
 4C 10 08   jmp label_0810

label_0832
 C9 87      cmp #$87
 D0 03      bne label_0839
 4C 10 08   jmp label_0810

label_0839
 C9 88      cmp #$88
 D0 06      bne label_0843
 20 8F 08   jsr label_088f
 4C 1D 08   jmp label_081d

label_0843
 C9 5F      cmp #$5f
 D0 03      bne label_084a
 4C D7 0E   jmp label_0ed7

label_084a
 C9 54      cmp #$54
 D0 06      bne label_0854
 20 D1 08   jsr label_08d1
 4C 20 08   jmp label_0820

label_0854
 C9 30      cmp #$30
 D0 06      bne label_085e
 20 26 09   jsr label_0926
 4C 1D 08   jmp label_081d

label_085e
 C9 31      cmp #$31
 D0 06      bne label_0868
 20 2C 09   jsr label_092c
 4C 1D 08   jmp label_081d

label_0868
 C9 32      cmp #$32
 D0 06      bne label_0872
 20 35 09   jsr label_0935
 4C 1D 08   jmp label_081d

label_0872
 C9 33      cmp #$33
 D0 06      bne label_087c
 20 3E 09   jsr label_093e
 4C 1D 08   jmp label_081d

label_087c
 C9 34      cmp #$34
 D0 06      bne label_0886
 20 47 09   jsr label_0947
 4C 1D 08   jmp label_081d

label_0886
 20 D1 08   jsr label_08d1
 20 BF 0E   jsr label_0ebf
 4C 1D 08   jmp label_081d

label_088f
 A9 38      lda #$38
 20 D1 08   jsr label_08d1
 20 BF 0E   jsr label_0ebf
 20 BF 0E   jsr label_0ebf
 A9 4C      lda #$4c
 20 D1 08   jsr label_08d1
 20 BF 0E   jsr label_0ebf
 20 BF 0E   jsr label_0ebf
 A9 44      lda #$44
 20 D1 08   jsr label_08d1
 20 BF 0E   jsr label_0ebf
 A9 46      lda #$46
 20 D1 08   jsr label_08d1
 20 BF 0E   jsr label_0ebf
 A9 4E      lda #$4e
 20 D1 08   jsr label_08d1
 20 BF 0E   jsr label_0ebf
 20 BF 0E   jsr label_0ebf
 A9 42      lda #$42
 20 D1 08   jsr label_08d1
 20 BF 0E   jsr label_0ebf
 A9 00      lda #$00
 20 07 09   jsr label_0907
 20 BF 0E   jsr label_0ebf
 60         rts

label_08d1
 A2 53      ldx #$53
 A0 45      ldy #$45
 8E 1D D4   stx $d41d
 8C 1E D4   sty $d41e
 8D 1F D4   sta $d41f
 20 BF 0E   jsr label_0ebf
 20 C7 0E   jsr label_0ec7
 60         rts

label_08e5
 A2 53      ldx #$53
 A0 49      ldy #$49
 8E 1D D4   stx $d41d
 8C 1E D4   sty $d41e
 8D 1F D4   sta $d41f
 20 BF 0E   jsr label_0ebf
 AE 1B D4   ldx $d41b
 AC 1C D4   ldy $d41c
 8E 05 09   stx $0905
 8C 06 09   sty $0906
 20 C7 0E   jsr label_0ec7
 60         rts
!byte $00,$00

label_0907
 8D 1F D4   sta $d41f
 8D FB 0E   sta $0efb
 A2 FF      ldx #$ff
 8E 1D D4   stx $d41d
 8E 1E D4   stx $d41e
 20 BF 0E   jsr label_0ebf
 A2 53      ldx #$53
 A0 4D      ldy #$4d
 8E 1D D4   stx $d41d
 8C 1E D4   sty $d41e
 20 BF 0E   jsr label_0ebf
 60         rts

label_0926
 A9 00      lda #$00
 20 07 09   jsr label_0907
 60         rts

label_092c
 AD FB 0E   lda $0efb
 49 01      eor #$01
 20 07 09   jsr label_0907
 60         rts

label_0935
 AD FB 0E   lda $0efb
 49 02      eor #$02
 20 07 09   jsr label_0907
 60         rts

label_093e
 AD FB 0E   lda $0efb
 49 04      eor #$04
 20 07 09   jsr label_0907
 60         rts

label_0947
 AD FB 0E   lda $0efb
 49 08      eor #$08
 20 07 09   jsr label_0907
 60         rts

label_0950
 20 E5 08   jsr label_08e5
 AD 05 09   lda $0905
 20 D2 FF   jsr $ffd2
 AD 06 09   lda $0906
 20 D2 FF   jsr $ffd2
 60         rts

label_0960
 20 01 0F   jsr label_0f01
 13 08      slo ( $08 ), y
 0E 96 73   asl $7396
 57 49      sre $49, x
 4E 9E 73   lsr $739e
 69 64      adc #$64
 20 05 75   jsr $7505
 4C 54 49   jmp $4954
!byte $4D,$41,$54,$45,$20,$9A,$63,$4F
!byte $4E,$46,$49,$47,$55,$52,$41,$54
!byte $4F,$52,$20,$99,$30,$2E,$32,$0D
!byte $0D,$00,$20,$F9,$0D,$20,$60,$0E
!byte $20,$01,$0F,$1F,$73,$69,$64,$20
!byte $74,$59,$50,$45,$3A,$20,$20,$20
!byte $9E,$36,$00,$AD,$F2,$0E,$A2,$36
!byte $20,$92,$0E,$20,$01,$0F,$35,$38
!byte $31,$20,$20,$1F,$2F,$20,$9E,$38
!byte $00,$AD,$F2,$0E,$A2,$38,$20,$92
!byte $0E,$20,$01,$0F,$35,$38,$30,$0D
!byte $00,$20,$01,$0F,$1F,$70,$49,$54
!byte $43,$48,$3A,$20,$20,$20,$20,$20
!byte $20,$00,$AD,$F4,$0E,$A2,$4E,$20
!byte $92,$0E,$20,$01,$0F,$6E,$74,$9E
!byte $73,$00,$AD,$F4,$0E,$A2,$4E,$20
!byte $92,$0E,$20,$01,$0F,$63,$1F,$20
!byte $20,$2F,$20,$00,$AD,$F4,$0E,$A2
!byte $50,$20,$92,$0E,$20,$01,$0F,$70
!byte $61,$9E,$6C,$0D,$00,$20,$01,$0F
!byte $1F,$6C,$65,$64,$20,$6D,$4F,$44
!byte $45,$3A,$20,$20,$20,$9E,$6E,$00
!byte $AD,$F6,$0E,$A2,$4E,$20,$92,$0E
!byte $20,$01,$0F,$4F,$54,$45,$20,$20
!byte $1F,$2F,$20,$9E,$69,$00,$AD,$F6
!byte $0E,$A2,$49,$20,$92,$0E,$20,$01
!byte $0F,$4E,$56,$45,$52,$54,$45,$44
!byte $1F,$20,$2F,$20,$9E,$72,$00,$AD
!byte $F6,$0E,$A2,$52,$20,$92,$0E,$20
!byte $01,$0F,$77,$0D,$00,$20,$01,$0F
!byte $1F,$73,$54,$41,$52,$54,$20,$62
!byte $45,$45,$50,$3A,$20,$9E,$62,$00
!byte $AD,$F9,$0E,$A2,$45,$20,$92,$0E
!byte $20,$01,$0F,$45,$45,$50,$1F,$20
!byte $20,$2F,$20,$9E,$6D,$00,$AD,$F9
!byte $0E,$A2,$44,$20,$92,$0E,$20,$01
!byte $0F,$55,$54,$45,$0D,$00,$20,$01
!byte $0F,$1F,$61,$55,$44,$49,$4F,$20
!byte $69,$4E,$3A,$20,$20,$20,$9E,$61
!byte $00,$AD,$FD,$0E,$A2,$4E,$20,$92
!byte $0E,$20,$01,$0F,$4C,$4C,$4F,$57
!byte $1F,$20,$2F,$20,$9E,$64,$00,$AD
!byte $FD,$0E,$A2,$46,$20,$92,$0E,$20
!byte $01,$0F,$49,$53,$41,$42,$4C,$45
!byte $20,$0D,$0D,$00,$20,$01,$0F,$1F
!byte $6D,$55,$54,$45,$3A,$20,$20,$20
!byte $20,$20,$20,$20,$9E,$30,$1F,$20
!byte $3D,$20,$00,$AD,$FB,$0E,$F0,$08
!byte $20,$01,$0F,$9A,$00,$4C,$02,$0B
!byte $20,$01,$0F,$96,$00,$20,$01,$0F
!byte $6E,$4F,$20,$63,$48,$41,$4E,$4E
!byte $45,$4C,$53,$20,$6D,$55,$54,$45
!byte $44,$0D,$00,$20,$01,$0F,$1F,$20
!byte $20,$20,$20,$20,$20,$20,$20,$20
!byte $20,$20,$20,$9E,$31,$1F,$20,$3D
!byte $20,$00,$A2,$01,$20,$A7,$0E,$20
!byte $01,$0F,$6D,$55,$54,$45,$20,$63
!byte $48,$41,$4E,$4E,$45,$4C,$20,$31
!byte $0D,$00,$20,$01,$0F,$1F,$20,$20
!byte $20,$20,$20,$20,$20,$20,$20,$20
!byte $20,$20,$9E,$32,$1F,$20,$3D,$20
!byte $00,$A2,$02,$20,$A7,$0E,$20,$01
!byte $0F,$6D,$55,$54,$45,$20,$63,$48
!byte $41,$4E,$4E,$45,$4C,$20,$32,$0D
!byte $00,$20,$01,$0F,$1F,$20,$20,$20
!byte $20,$20,$20,$20,$20,$20,$20,$20
!byte $20,$9E,$33,$1F,$20,$3D,$20,$00
!byte $A2,$04,$20,$A7,$0E,$20,$01,$0F
!byte $6D,$55,$54,$45,$20,$63,$48,$41
!byte $4E,$4E,$45,$4C,$20,$33,$0D,$00
!byte $20,$01,$0F,$1F,$20,$20,$20,$20
!byte $20,$20,$20,$20,$20,$20,$20,$20
!byte $9E,$34,$1F,$20,$3D,$20,$00,$A2
!byte $08,$20,$A7,$0E,$20,$01,$0F,$6D
!byte $55,$54,$45,$20,$64,$49,$47,$49
!byte $53,$0D,$0D,$00,$20,$01,$0F,$1F
!byte $72,$45,$2D,$69,$4E,$49,$54,$3A
!byte $20,$20,$20,$20,$9A,$72,$45,$2D
!byte $69,$4E,$49,$9E,$74,$9A,$20,$63
!byte $48,$49,$50,$0D,$0D,$00,$20,$01
!byte $0F,$1F,$63,$4F,$4D,$4D,$41,$4E
!byte $44,$53,$3A,$20,$20,$20,$9E,$66
!byte $33,$9A,$20,$73,$48,$4F,$57,$20
!byte $63,$4F,$4E,$46,$49,$47,$20,$76
!byte $41,$4C,$55,$45,$53,$0D,$00,$20
!byte $01,$0F,$9E,$20,$20,$20,$20,$20
!byte $20,$20,$20,$20,$20,$20,$20,$66
!byte $35,$9A,$20,$72,$45,$46,$52,$45
!byte $53,$48,$0D,$00,$20,$01,$0F,$9E
!byte $20,$20,$20,$20,$20,$20,$20,$20
!byte $20,$20,$20,$20,$66,$37,$9A,$20
!byte $73,$45,$54,$20,$64,$45,$46,$41
!byte $55,$4C,$54,$53,$0D,$00,$20,$01
!byte $0F,$9E,$20,$20,$20,$20,$20,$20
!byte $20,$20,$20,$20,$20,$20,$5F,$9A
!byte $20,$20,$65,$58,$49,$54,$20,$70
!byte $52,$4F,$47,$52,$41,$4D,$0D,$00
!byte $20,$60,$0E,$20,$01,$0F,$0D,$96
!byte $73,$45,$4C,$45,$43,$54,$45,$44
!byte $20,$1F,$2F,$9A,$20,$64,$45,$53
!byte $45,$4C,$45,$43,$54,$45,$44,$20
!byte $20,$20,$20,$20,$20,$20,$20,$20
!byte $99,$73,$43,$48,$45,$4D,$41,$2F
!byte $61,$69,$63,$13,$00,$60

label_0cb3
 20 01 0F   jsr label_0f01
 93 00      ahx $2000, x
 20 60 0E   jsr label_0e60
 20 01 0F   jsr label_0f01
 1C 69 44   nop $4469, x
 45 4E      eor $4e
 54 49      nop $49, x
 46 49      lsr $49
 43 41      sre ( $41, x)
 54 49      nop $49, x
 4F 4E 3A   sre $3a4e
 20 96 00   jsr $0096
 A9 44      lda #$44
 20 50 09   jsr label_0950
 A9 45      lda #$45
 20 50 09   jsr label_0950
 20 01 0F   jsr label_0f01
 0D 00 20   ora $2000
 01 0F      ora ( $0f, x)
 1C 76 45   nop $4576, x
 52         jam
 53 49      sre ( $49 ), y
 4F 4E 3A   sre $3a4e
 20 20 20   jsr $2020
 20 20 20   jsr $2020
 20 20 96   jsr $9620
 00         brk
 A9 56      lda #$56
 20 50 09   jsr label_0950
 20 01 0F   jsr label_0f01
 0D 00 20   ora $2000
 01 0F      ora ( $0f, x)
 1C 66 55   nop $5566, x
 4E 43 54   lsr $5443
 49 4F      eor #$4f
 4E 20 61   lsr $6120
 53 3A      sre ( $3a ), y
 20 20 20   jsr $2020
 20 96 00   jsr $0096
 A9 46      lda #$46
 20 50 09   jsr label_0950
 20 01 0F   jsr label_0f01
 0D 00 20   ora $2000
 01 0F      ora ( $0f, x)
 1C 63 4C   nop $4c63, x
 4F 43 4B   sre $4b43
 3A         nop
 20 20 20   jsr $2020
 20 20 20   jsr $2020
 20 20 20   jsr $2020
 20 96 00   jsr $0096
 A9 43      lda #$43
 20 50 09   jsr label_0950
 20 01 0F   jsr label_0f01
 0D 00 20   ora $2000
 01 0F      ora ( $0f, x)
 1C 6C 65   nop $656c, x
 64 20      nop $20
 63 4F      rra ( $4f, x)
 4E 46 49   lsr $4946
 47 3A      sre $3a
 20 20 20   jsr $2020
 20 20 96   jsr $9620
 00         brk
 A9 4C      lda #$4c
 20 50 09   jsr label_0950
 20 01 0F   jsr label_0f01
 0D 00 20   ora $2000
 01 0F      ora ( $0f, x)
 1C 73 54   nop $5473, x
 41 52      eor ( $52, x)
 54 20      nop $20, x
 62         jam
 45 45      eor $45
 50 3A      bvc label_0da9
 20 20 20   jsr $2020
 20 20 96   jsr $9620
 00         brk
 A9 42      lda #$42
 20 50 09   jsr label_0950
 20 01 0F   jsr label_0f01
 0D 00 20   ora $2000
 01 0F      ora ( $0f, x)
 1C 6D 55   nop $556d, x
 54 45      nop $45, x
 20 62 49   jsr $4962
 54 4D      nop $4d, x
 41 53      eor ( $53, x)
 4B 3A      alr #$3a
 20 20 20   jsr $2020
 96 30      stx $30, y
 00         brk
 A9 4D      lda #$4d
 20 E5 08   jsr label_08e5
 AE 06 09   ldx $0906
 BD E2 0E   lda $0ee2, x
 20 D2 FF   jsr $ffd2
 20 01 0F   jsr label_0f01
 0D 00 20   ora $2000
 01 0F      ora ( $0f, x)
 1C 61 55   nop $5561, x
 44 49      nop $49
 4F 20 49   sre $4920
 4E 3A 20   lsr $203a
 20 20 20   jsr $2020
 20 20 20   jsr $2020
 96 00      stx $00, y
 A9 41      lda #$41
 20 50 09   jsr label_0950
 20 01 0F   jsr label_0f01
 0D 00 20   ora $2000
 60         rts
!byte $0E,$20,$01,$0F,$0D,$00,$20,$01
!byte $0F,$9E,$70,$52,$45,$53,$53,$20
!byte $61,$4E,$59,$20,$6B,$45,$59,$20
!byte $66,$4F,$52,$20,$6D,$41,$49,$4E
!byte $20,$6D,$45,$4E,$55,$0D,$00,$20
!byte $E4,$FF,$F0,$FB,$60,$A9,$46,$20
!byte $E5,$08,$AE,$05,$09,$AC,$06,$09
!byte $8E,$F2,$0E,$8C,$F3,$0E,$A9,$43
!byte $20,$E5,$08,$AE,$05,$09,$AC,$06
!byte $09,$8E,$F4,$0E,$8C,$F5,$0E,$A9
!byte $4C,$20,$E5,$08,$AE,$05,$09,$AC
!byte $06,$09,$8E,$F6,$0E,$8C,$F7,$0E
!byte $A9,$42,$20,$E5,$08,$AE,$05,$09
!byte $AC,$06,$09,$8E,$F8,$0E,$8C,$F9
!byte $0E,$A9,$4D,$20,$E5,$08,$AE,$05
!byte $09,$AC,$06,$09,$8E,$FA,$0E,$8C
!byte $FB,$0E,$A9,$41,$20,$E5,$08,$AE
!byte $05,$09,$AC,$06,$09,$8E,$FC,$0E
!byte $8C,$FD,$0E,$60

label_0e60
 20 01 0F   jsr label_0f01
 97 00      sax $00, y
 20 01 0F   jsr label_0f01
 60         rts
!byte $60,$60,$60,$60,$60,$60,$60,$60
!byte $60,$60,$60,$60,$60,$60,$60,$60
!byte $60,$60,$60,$60,$60,$60,$60,$60
!byte $60,$60,$60,$60,$60,$60,$60,$60
!byte $60,$60,$60,$60,$60,$60,$60,$00
!byte $60,$8E,$A6,$0E,$CD,$A6,$0E,$D0
!byte $06,$20,$01,$0F,$96,$00,$60,$20
!byte $01,$0F,$9A,$00,$60,$00,$8E,$BE
!byte $0E,$AD,$FB,$0E,$2D,$BE,$0E,$F0
!byte $06,$20,$01,$0F,$96,$00,$60,$20
!byte $01,$0F,$9A,$00,$60,$00

label_0ebf
 A2 C8      ldx #$c8

label_0ec1
 EA         nop
 EA         nop
 CA         dex
 D0 FB      bne label_0ec1
 60         rts

label_0ec7
 A2 FF      ldx #$ff
 A0 FF      ldy #$ff
 A9 FF      lda #$ff
 8E 1D D4   stx $d41d
 8C 1E D4   sty $d41e
 8D 1F D4   sta $d41f
 60         rts

label_0ed7
 20 C7 0E   jsr label_0ec7
 20 01 0F   jsr label_0f01
 93 8E      ahx $058e, x
 05 00      ora $00
 60         rts
!byte $30,$31,$32,$33,$34,$35,$36,$37
!byte $38,$39,$61,$62,$63,$64,$65,$66
!byte $00,$00,$00,$00,$00,$00,$00,$00
!byte $00,$00,$00,$00,$00,$00,$00

label_0f01
 8D 00 0F   sta $0f00
 8E FE 0E   stx $0efe
 8C FF 0E   sty $0eff
 68         pla
 8D 1B 0F   sta $0f1b
 68         pla
 8D 1C 0F   sta $0f1c

label_0f12
 EE 1B 0F   inc $0f1b
 D0 03      bne label_0f1a
 EE 1C 0F   inc $0f1c

label_0f1a
 AD AA AA   lda $aaaa
 F0 06      beq label_0f25
 20 D2 FF   jsr $ffd2
 4C 12 0F   jmp label_0f12

label_0f25
 AD 1C 0F   lda $0f1c
 48         pha
 AD 1B 0F   lda $0f1b
 48         pha
 AD 00 0F   lda $0f00
 AE FE 0E   ldx $0efe
 AC FF 0E   ldy $0eff
 60         rts
