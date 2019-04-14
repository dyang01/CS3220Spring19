; Addresses for I/O
.NAME	HEX = 	0xFFFFF000
.NAME	LEDR =	0xFFFFF020
.NAME	KEY = 	0xFFFFF080
.NAME 	TIMER = 0xFFFFF104

; IDN Values
.NAME	BT	= 00
.NAME	SW	= 01
.NAME	TI	= 10

; Processor Initialization
	.ORG	0x100
	XOR		Zero, Zero, Zero			; Zero the Zero register
	ADDI	Zero, A0, 2					; Sets default speed to be 2
	SW		A0, HEX(Zero)				; Displays speed on HEX 	
	ADD 	A1, Zero, Zero 				; Sets blink state to 0
	ADDI  	Zero, A2, 250 				; A2 = 250
	ADDI 	Zero, S0, TIMER 			; S0 = address of timer.
	ADDI 	Zero, S1, 500 				; S1 = blink time in millis . S1 = 500 ms (default)
	SW 		S1, TIMER(Zero)				; Sets TLIM = 500 ms

InfiniteLoop:
	BR		InfiniteLoop 				; Main Loop. Interrupts should occur here.

; Currently a memory leak from adding to stack and never removing from stack.
InterruptHandler:						; Begins at interrupt start.
; _____________________________________________________________________ NOT SURE IF GOOD
	ANDI	PCS, PCS, 0xFFFFFFFE		; Diasbled interrupts. Sets IE = 0
	ADDI	SSP, SSP, -8				; Grows stack. Saves 2 regs.
	SW		T0, 0(SSP)					; Saves T0 to system stack
	SW		T1, 4(SSP)					; Saves T1 to system stack
; _____________________________________________________________________
	RSR		T0, IDN						; Get cause of interrupt.
	BEQ		T0, Zero, Timer				; If IDN == 0, then Timer interrupt
	ADDI 	Zero, T1, 1
	BNE 	T1, T0, InfiniteLoop 		; If NOT a KEY, then ignore interrupt. Back to main loop.
										; This code is ONLY executed if KEY interrupt
	LW 		T0, KEY(Zero)				; Loads T0 with state of all 4 KEY values
	BEQ 	T0, T1, Slow 				; If KEY[0] == 1 then Slow
	BR 		Fast 						; If not KEY[0] then KEY[1].

Timer:
	BEQ 	A1, Zero, UpperBlink 		; Check if state == 0. Then UpperBlink
	ADDI 	Zero, T0, 1
	BEQ		A1, T0, LowerBlink 			; Check if state == 1. Then LowerBlink
	BR 		FullBlink		 			; Must be FullBlink

UpperBlink:
	ADDI 	Zero, T0, 0x3E0 			; 3E0 is top 5 LEDs.
	SW 		T0, LEDR(Zero)				; Writes UpperBlink to LEDR.
	ADDI 	A1, A1, 1 					; Increments state to 1.
	BR 		InfiniteLoop 				; Returns to main loop.	

LowerBlink:
	ADDI 	Zero, T0, 0x1F 				; 1F is bottom 5 LEDs
	SW 		T0, LEDR(Zero)				; Writes UpperBlink to LEDR.
	ADDI 	A1, A1, 1 					; Increments state to 2.
	BR 		InfiniteLoop 				; Returns to main loop. 

FullBlink:
	ADDI 	Zero, T0, 0x3FF				; 3FF is bottom 5 LEDs
	SW 		T0, LEDR(Zero)				; Writes UpperBlink to LEDR.
	ADDI 	A1, A1, -2 					; Increments state to 0.
	BR 		InfiniteLoop 				; Returns to main loop. 

Fast:
	ADDI 	Zero, T0, 1
	BEQ 	T0, A0, InfiniteLoop 		; If A0 (state) == 1, already at min. Ignore.
	ADDI 	A0, A0, -1 					; Decrement state.
	SW 		A0, HEX(Zero) 				; Display new state on HEX
	ADDI 	S1, S1, -250 				; Decrease blink time by 250 ms
	SW 		S1, TIMER(Zero) 			; Set new TLIM
	BR 		InfiniteLoop

Slow:
	ADDI 	Zero, T0, 8
	BEQ 	T0, A0, InfiniteLoop 		; If A0 (state) == 8, already at max. Ignore.
	ADDI 	A0, A0, 1 					; Increment state.
	SW 		A0, HEX(Zero) 				; Display new state on HEX
	ADDI 	S1, S1, 250 				; Increase blink time by 250 ms
	SW 		S1, TIMER(Zero) 			; Set new TLIM
	BR 		InfiniteLoop