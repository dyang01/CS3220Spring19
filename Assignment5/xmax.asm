.ORG 	0x10
InterruptHandler:
	; Interrupts are disabled by HW before this
	RSR		T0, IDN 								; T0 is interrupt device number
	LW 		T1, TI(Zero)
	BEQ 	T0, T1, TimerHandler 		; Is a timer interrupt
	LW 		T1, KY(Zero)
	BEQ 	T0, T1, KeyHandler 			; Is a key interrupt
	LW 		T1, SW(Zero)
	BEQ 	T0, T1, SwitchHandler 	; Is a switch interrupt
	; Execution should not occur here!!
	RETI

TimerHandler: ; Branch to UpperBlink, LowerBlink, or FullBlink based on state (0 -> 8) A1. 
	BNE 	A3, Zero, NoBlink 			; if blink_state = 1, then turn off LEDs.
	ADDI 	Zero, T1, 3 						; T1 = 3.
	BLT 	A1, T1, UpperBlink 			; turn on upper LED if state < 3 	
	ADDI	T1, T1, 3 							; T1 = 6.
	BLT 	A1, T1, LowerBlink 			; turn on lower LED if state < 6
	ADDI 	T1, T1, 3 							; T1 = 9
	BLT 	A1, T1, FullBlink 			; turn on full LED if state < 9
	RETI

KeyHandler: 	
	LW 		T1, KEY(Zero) 					; Loads T1 with state of all 4 KEY values
	BEQ 	T0, T1, Slow 						; T0 is already 1 from KEY IDN == 1. If KEY 0 pressed, then 0001. Slow down.
	BR Fast
	RETI

SwitchHandler:
		LW 		T1, SWITCH(Zero) 				; Loads T1 with state of all 10 SWITCH values.
		LW 		S0, BIT0(Zero) 					; checks for position of each switch
		BGE 	T1, S0, Not0
		ADDI 	Zero, S2, 0
		RETI
	Not0:
		LW 		S0, BIT1(Zero)
		BGE 	T1, S0, Not1
		ADDI 	Zero, S2, 1
		RETI
	Not1:
		LW 		S0, BIT2(Zero)
		BGE 	T1, S0, Not2
		ADDI 	Zero, S2, 2
		RETI
	Not2:
		LW 		S0, BIT3(Zero)
		BGE 	T1, S0, Not3
		ADDI 	Zero, S2, 3
		RETI
	Not3:
		ADDI 	Zero, S2, 4
		RETI


; Processor Initialization
	.ORG	0x100
	XOR		Zero, Zero, Zero			; Zero the Zero register
	ADDI	Zero, A0, 2					; Sets default speed to be 2
	SW		A0, HEX(S2)				; Displays speed on HEX 	
	ADD 	A1, Zero, Zero 				; Sets blink state to 0
	ADD 	A3, Zero, Zero 				; Sets on/off state to 0
	ADDI 	Zero, A2, 250 				; A2 = 250
	ADDI 	Zero, S1, 500 				; S1 = blink time in millis . S1 = 500 ms (default)
	SW 		S1, TIMER(Zero)				; Sets TLIM = 500 ms
	ADD 	S2, Zero, Zero 				; HEX selection

InfiniteLoop:
	BR		InfiniteLoop 				; Main Loop. Interrupts should occur here.

UpperBlink:
	ADDI 	Zero, T0, 0x3E0 			; 3E0 is top 5 LEDs.
	SW 		T0, LEDR(Zero)				; Writes UpperBlink to LEDR.
	ADDI 	A1, A1, 1 					; Increments state
	ADDI 	A3, A3, 1 					; Increments blink_state
	RETI							 				; Returns to main loop.	

LowerBlink:
	ADDI 	Zero, T0, 0x1F 				; 1F is bottom 5 LEDs
	SW 		T0, LEDR(Zero)				; Writes LowerBlink to LEDR.
	ADDI 	A1, A1, 1 					; Increments state
	ADDI 	A3, A3, 1 					; Increments blink_state
	RETI							 				; Returns to main loop. 

FullBlink:
	ADDI 	Zero, T0, 0x3FF				; 3FF is all LEDs
	SW 		T0, LEDR(Zero)				; Writes FullBlink to LEDR.
	ADDI 	Zero, T0, 9 				; T0 = 9
	ADDI 	A1, A1, 1 					; Increments state
	ADDI 	A3, A3, 1 					; Increments blink_state
	BNE 	T0, A1, EndInterruptHandler 	; If T0 == A1 then reset A1. else go to back to main loop
	ADDI 	Zero, A1, 0					; State = 0
	RETI						 				; Returns to main loop. 

NoBlink:
	ADDI 	Zero, T0, 0x0 					; Turns off LEDs
	SW 		T0, LEDR(Zero) 					; Writes NoBlink to LEDR.
	ADD 	A3, Zero, Zero					; blink_state = 0;
	RETI							  					; Returns to main loop.

Fast:
	ADDI 	Zero, T0, 1
	BEQ 	T0, A0, EndInterruptHandler 		; If A0 (state) == 1, already at min. Ignore.
	ADDI 	A0, A0, -1 					; Decrement state.
	SW 		A0, HEX(S2) 				; Display new state on HEX
	ADDI 	S1, S1, -250 				; Decrease blink time by 250 ms
	SW 		S1, TIMER(Zero) 			; Set new TLIM
	RETI

Slow:
	ADDI 	Zero, T0, 8
	BEQ 	T0, A0, EndInterruptHandler 		; If A0 (state) == 8, already at max. Ignore.
	ADDI 	A0, A0, 1 					; Increment state.
	SW 		A0, HEX(S2) 				; Display new state on HEX
	ADDI 	S1, S1, 250 				; Increase blink time by 250 ms
	SW 		S1, TIMER(Zero) 			; Set new TLIM
	RETI

EndInterruptHandler:
	RETI

; Addresses for I/O
.NAME	HEX = 	0xFFFFF000
.NAME	LEDR =	0xFFFFF020
.NAME	KEY = 	0xFFFFF080
.NAME SWITCH = 0xFFFFF090
.NAME TIMER = 0xFFFFF104

; IDN Values
.NAME	TI	= 00
.NAME	KY	= 01
.NAME	SW	= 10

; Bit masks
.NAME	BIT0 = 0x1
.NAME BIT1 = 0x2
.NAME	BIT2 = 0x4
.NAME	BIT3 = 0x8
.NAME	BIT4 = 0x10