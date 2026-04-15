

SIDFX_DETECT:

// SYNC WITH SIDFX
	ldy #$0f
!:	jsr SCIsync		//bring SCI state machine into a known state
	dey
	bpl !-

/*// PNP hardware detection 
	lda #$80		
	jsr SCIput
	lda #$50		
	jsr SCIput		
	lda #$4e		
	jsr SCIput
	lda #$50		
	jsr SCIput

// Store PNP string 
	jsr SCIget		//Read vendor ID LSB  
	sta PNP+0
	jsr SCIget		//Read vendor ID MSB
	sta PNP+1
	jsr SCIget		//Read product ID LSB
	sta PNP+2
	jsr SCIget		//Read product ID MSB
	sta PNP+3

// Compare PNP string
	lda #$45	
	cmp PNP+0
	bne SIDFX_not_found
	lda #$4c
	cmp PNP+1
	bne SIDFX_not_found
	lda #$12
	cmp PNP+2
	bne SIDFX_not_found
	lda #$58
	cmp PNP+3
	bne SIDFX_not_found
*/

// PNP hardware detection 
	ldy #0
	
	lda PNPstring,y	
	jsr SCIput




	jmp SIDFX_found
;---------------------------------------------------------------------------------------------------		
SIDFX_not_found:
	rts

PNPstring:	
	.byte $80,$50,$4e,$50		// Init PNP
	.byte $45,$4c,$12,$58		// Compare string
	
;---------------------------------------------------------------------------------------------------		
SIDFX_found:
// SIDFX stealthmode OFF
	jsr SIDFX_ControlRegisters_unhide		
		
// Get SW1 position (optionally warn user if SW1 is not in center position aka manual override)
// if user hasnt selected AUTO, there is no point in continuing
	lda $d41d
	and #%00110000
	bne SIDFX_SW1_NOT_CENTER

// okay, we have control... check which SIDs are installed, 
		
// Get SID1 model
	lda $d41e			// bit 0+1
	and #%00000011
		// %00 = none, %01 = 6581, %10 = 8580, %11 = reserved for future use 
	
// Get SID2 model
		lda $d41e			// bit 2+3
		and #%00001100
		
		// %00 = none, %01 = 6581, %10 = 8580, %11 = reserved for future use 

		
		

		

		
/*		
// Get Playback-mode
		lda $d41d			
		and #$07
*/

//Get stereo capability (are all grabbers installed?)
/*		lda $d41d			
		and #$08	
		bne SIDFX_STEREO_NOT_CONNECTED
*/	



// Set Playback-mode


		//your code
		sta $d41d			

// SIDFX stealthmode ON
		jsr SIDFX_ControlRegisters_hide		

		rts

		
;---------------------------------------------------------------------------------------------------

SIDFX_ControlRegisters_unhide:
		lda #$c0		
		jsr SCIput
		lda #$45
		jsr SCIput

		jsr SCIsync		//wait for registers to become ready
		rts

;---------------------------------------------------------------------------------------------------

SIDFX_ControlRegisters_hide:
		lda #$c1		
		jsr SCIput
		lda #$44
		jsr SCIput

		jsr SCIsync		//wait for registers to become hidden
		rts

/*---------------------------------------------------------------------------------------------------
	Exchange SCI byte

	A	must contain the byte to send
	A	will contain the byte received

	X	modified
---------------------------------------------------------------------------------------------------*/

SCIgetW:
		ldx #$01		//>10us delay to allow SCI ready flag to become available
!:		dex
		bpl !-

SCIget:
!:		lda $d41f		//read SCI ready flag
		bpl !-			//wait until data ready

SCIsync:
		lda #$00		//"nop" SCI command

SCIput:

/* Alternative way of doing it... 		
		sta ByteHelper+1
		
		ldx #$07		// Byte exchange START
		stx $d41e		

ByteHelper:
		lda #00
		sta $d41f		// transmit bit 7
		ldx $d41f		// why?
		lsr
		
		sta $d41f		// transmit bit 6
		ldx $d41f		// why?
		lsr
		
*/
		


/* LOTUS STYLE
		ldx #$07		// transfer 8 bits (MSB first)
		stx $d41e		// bring SCI sync signal low

!:		pha				//save data byte

		sta $d41f		//transmit bit 7
		lda $d41f		//receive bit 0
		ror				//push bit 0 to carry flag (why?)
		
		pla				//restore data byte

		rol				//shift transmitted bit out and received bit in
		dex				//next bit
		bpl !-			//done?

		// X = $FF 
		stx $d41e		//bring SCI sync signal high (%10000000)
		rts
*/

