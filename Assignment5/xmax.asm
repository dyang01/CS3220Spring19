.ORG 	0x10
InterruptHandler:
	; Interrupts are disabled by HW before this
	RSR		T0, IDN
	LW 		T1, TM(0)
	BNE 	T0, T1, NotTimer
	; Is a timer interrupt
	; Branch to UpperBlink, LowerBlink, or FullBlink based on blink state (0 -> 8) A1
	ADD 	T0, A1, Zero
	ADDI 	Zero, T1, 3
	

	BR EndInterruptHandler
	NotTimer:
	LW 		T1, BT(0)
	BNE 	T0, T1, NotButton
	; Is a button interrupt

	BR EndInterruptHandler
	NotButton:
	LW 		T1, SW(0)
	BNE 	T0, T1, NotSwitch
	; Is a switch interrupt

	BR EndInterruptHandler
	NotSwitch:
	; Is a key interrupt

	EndInterruptHandler:
	RETI


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

UpperBlink:
	ADDI 	Zero, T0, 0x3E0 			; 3E0 is top 5 LEDs.
	SW 		T0, LEDR(Zero)				; Writes UpperBlink to LEDR.
	ADDI 	A1, A1, 1 					; Increments state
	BR 		InfiniteLoop 				; Returns to main loop.	

LowerBlink:
	ADDI 	Zero, T0, 0x1F 				; 1F is bottom 5 LEDs
	SW 		T0, LEDR(Zero)				; Writes LowerBlink to LEDR.
	ADDI 	A1, A1, 1 					; Increments state
	BR 		InfiniteLoop 				; Returns to main loop. 

FullBlink:
	ADDI 	Zero, T0, 0x3FF				; 3FF is all LEDs
	SW 		T0, LEDR(Zero)				; Writes FullBlink to LEDR.
	ADDI 	Zero, A1, 0					; State = 0
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

; Addresses for I/O
.NAME	HEX = 	0xFFFFF000
.NAME	LEDR =	0xFFFFF020
.NAME	KEY = 	0xFFFFF080
.NAME 	TIMER = 0xFFFFF104

; IDN Values
.NAME	BT	= 00
.NAME	SW	= 01
.NAME	TI	= 10

; Bit masks
.NAME	BIT0 = 0x1
.NAME 	BIT1 = 0x2
.NAME	BIT2 = 0x4
.NAME	BIT3 = 0x8
.NAME	BIT4 = 0x10
.NAME	BIT5 = 0x11