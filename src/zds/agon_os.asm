;
; Title:	BBC Basic for AGON - MOS stuff
; Author:	Dean Belfield
; Created:	04/12/2024
; Last Updated:	04/12/2024
;
; Modinfo:

			.ASSUME	ADL = 0
				
			INCLUDE	"equs.inc"
			INCLUDE "macros.inc"
			INCLUDE "mos_api.inc"	; In MOS/src
		
			SEGMENT CODE
			
			XDEF	OSWORD
			XDEF	OSBYTE
			XDEF	OSINIT
			XDEF	OSOPEN
			XDEF	OSSHUT
			XDEF	OSLOAD
			XDEF	OSSAVE
			XDEF	OSLINE
			XDEF	OSSTAT
			XDEF	OSWRCH
			XDEF	OSRDCH
			XDEF	OSBGET
			XDEF	OSBPUT
			XDEF	OSCLI
			XDEF	PROMPT
			XDEF	GETPTR
			XDEF	PUTPTR
			XDEF	GETEXT
			XDEF	TRAP
			XDEF	LTRAP
			XDEF	BYE
			XDEF	RESET
			XDEF	ESCSET
			
			XREF	EXTERR
			XREF	VBLANK_INIT
			XREF	USER
			XREF	COUNT0
			XREF	COUNT1
			XREF	GETCSR 
			XREF	GETSCHR_1
			XREF	NULLTOCR
			XREF	CRLF
			XREF	FLAGS
			XREF	KEYASCII
			XREF	KEYDOWN

;OSINIT - Initialise RAM mapping etc.
;If BASIC is entered by BBCBASIC FILENAME then file
;FILENAME.BBC is automatically CHAINed.
;   Outputs: DE = initial value of HIMEM (top of RAM)
;            HL = initial value of PAGE (user program)
;            Z-flag reset indicates AUTO-RUN.
;  Destroys: A,D,E,H,L,F
;
OSINIT:			CALL	VBLANK_INIT
			XOR	A
;			LD	(FLAGS), A		; Clear flags and set F = Z
			LD 	HL, USER
			LD	DE, RAM_Top
			LD	E, A			; Page boundary
			RET	

; PROMPT: output the input prompt
;
PROMPT: 		LD	A,'>'			; Falls through to OSWRCH

; OSWRCH: Write a character out to the ESP32 VDU handler via the MOS
; Parameters:
; - A: Character to write
;
OSWRCH:			RST.LIS	10h			; Output the character to MOS
			RET

; OSRDCH
;
OSRDCH:			RET

; OSLINE: Invoke the line editor
;
OSLINE:			LD 	E, 1			; Default is to clear the buffer

; Entry point to line editor that does not clear the buffer
; Parameters:
; - HL: addresses destination buffer (on page boundary)
; Returns:
; -  A: 0
; NB: Buffer filled, terminated by CR
; 
OSLINE1:		PUSH	IY			
			PUSH	HL			; Buffer address
			LD	BC, 256			; Buffer length
			MOSCALL	mos_editline		; Call the MOS line editor
			POP	HL			; Pop the address
			POP	IY
			PUSH	AF			; Stack the return value (key pressed)
			CALL	NULLTOCR		; Turn the 0 character to a CR
			CALL	CRLF			; Display CRLF
			POP	AF
;			CP	1Bh 			; Check if ESC terminated the input
;			JP	Z, LTRAP1 		; Yes, so do the ESC thing
;			LD	A, (FLAGS)		; Otherwise
;			RES	7, A 			; Clear the escape flag
;			LD	(FLAGS), A 
			CALL	WAIT_VBLANK 		; Wait a frame 
 			XOR	A			; Return A = 0
			LD	(KEYDOWN), A 
			LD	(KEYASCII), A
			RET		

TRAP:
LTRAP:			XOR	A			; TODO: See patch.asm
ESCSET:			RET

; RESET
;
RESET:			RET				; Yes this is fine

; OSWORD
;
OSWORD:			RET				; TODO

;
; OSBYTE
; Parameters:
; - A: FX #
; - L: First parameter
; - H: Second parameter
;
OSBYTE:			CP	0BH			; Keyboard auto-repeat delay
			JR	Z, OSBYTE_0B
			CP	0CH			; Keyboard auto-repeat rate
			JR	Z, OSBYTE_0C
			CP	13H			; Wait for vblank
			JR	Z, OSBYTE_13		
			CP	76H			; Set keyboard LED
			JR	Z, OSBYTE_76
			CP	81H			; Read the keyboard
			JP	Z, OSBYTE_81
			CP	86H			; Get cursor coordinates
			JP	Z, OSBYTE_86
			CP	87H			; Fetch current mode and character under cursor
			JP	Z, OSBYTE_87
			CP	A0H			; Fetch system variable
			JP	Z, OSBYTE_A0		
;
; Anything else trips an error
;
HUH:    		LD      A,254			; Bad command error
        		CALL    EXTERR
        		DB    	"Bad command"
        		DEFB    0				

; OSBYTE 0x0B (FX 11,n): Keyboard auto-repeat delay
; Parameters:
; - HL: Repeat delay
;
OSBYTE_0B:		VDU	23
			VDU	0
			VDU	vdp_keystate
			VDU	L
			VDU	H 
			VDU	0
			VDU 	0
			VDU	255
			RET 

; OSBYTE 0x0C (FX 12,n): Keyboard auto-repeat rate
; Parameters:
; - HL: Repeat rate
;
OSBYTE_0C:		VDU	23
			VDU	0
			VDU	vdp_keystate
			VDU	0
			VDU 	0
			VDU	L
			VDU	H 
			VDU	255
			RET 

; OSBYTE 0x13 (FX 19): Wait for vertical blank interrupt
;
OSBYTE_13:		CALL	WAIT_VBLANK
			LD	L, 0			; Returns 0
			JP	COUNT0
;
; OSBYTE 0x76 (FX 118,n): Set Keyboard LED
; Parameters:
; - L: LED (Bit 0: Scroll Lock, Bit 1: Caps Lock, Bit 2: Num Lock)
;
OSBYTE_76:		VDU	23
			VDU	0
			VDU	vdp_keystate
			VDU	0
			VDU 	0
			VDU	0
			VDU	0 
			VDU	L
			RET 

; OSBYTE 0x81: Read the keyboard
; Parameters:
; - HL = Time to wait (centiseconds)
; Returns:
; - F: Carry reset indicates time-out
; - A: If carry set, A = character typed
; Destroys: A,D,E,H,L,F
;
OSBYTE_81:		XOR	A
			RET

; OSBYTE 0x86: Fetch cursor coordinates
; Returns:
; - DE: X Coordinate (POS)
; - HL: Y Coordinate (VPOS)
;
OSBYTE_86:		PUSH	IX			; Get the system vars in IX
			MOSCALL	mos_sysvars		; Reset the semaphore
			RES.LIL	0, (IX+sysvar_vpd_pflags)
			VDU	23
			VDU	0
			VDU	vdp_cursor
$$:			BIT.LIL	0, (IX+sysvar_vpd_pflags)
			JR	Z, $B			; Wait for the result
			LD 	D, 0
			LD	H, D
			LD.LIL	E, (IX + sysvar_cursorX)
			LD.LIL	L, (IX + sysvar_cursorY)			
			POP	IX			
			RET	

; OSBYTE 0x87: Fetch current mode and character under cursor
;
OSBYTE_87:		PUSH	IX
			CALL	GETCSR			; Get the current screen position
			CALL	GETSCHR_1		; Read character from screen
			LD	L, A 
			MOSCALL	mos_sysvars
			LD.LIL	H, (IX+sysvar_scrMode)	; H: Screen mode
			POP	IX
			JP	COUNT1
			
; OSBYTE 0xA0: Fetch system variable
; Parameters:
; - L: The system variable to fetch
;
OSBYTE_A0:		PUSH	IX
			MOSCALL	mos_sysvars		; Fetch pointer to system variables
			LD.LIL	BC, 0			
			LD	C, L			; BCU = L
			ADD.LIL	IX, BC			; Add to IX
			LD.LIL	L, (IX + 0)		; Fetch the return value
			POP	IX
			JP 	COUNT0

; OSCLI
;
OSCLI:			RET

; Helper Functions
;
WAIT_VBLANK:		PUSH 	IX			; Wait for VBLANK interrupt
			MOSCALL	mos_sysvars		; Fetch pointer to system variables
			LD.LIL	A, (IX + sysvar_time + 0)
$$:			CP.LIL 	A, (IX + sysvar_time + 0)
			JR	Z, $B
			POP	IX
			RET

; Currently unimplemented stuff
;
SORRY:			MACRO 	text 
			XOR	A
			CALL	EXTERR 
			DEFB	'Sorry - '
			DEFB	text
			DEFB	0 
			ENDMACRO 

OSSHUT:			RET		; TODO: This just returns to prevent an error when running BASIC

OSOPEN:			SORRY 'OSOPEN'
OSLOAD:			SORRY 'OSLOAD'
OSSAVE:			SORRY 'OSSAVE'
OSSTAT:			SORRY 'OSSTAT'
OSBGET:			SORRY 'OSBGET'
OSBPUT:			SORRY 'OSBPUT'
GETPTR:			SORRY 'GETPTR'
PUTPTR:			SORRY 'PUTPTR'
GETEXT:			SORRY 'GETEXT'
BYE:			SORRY 'BYE'
