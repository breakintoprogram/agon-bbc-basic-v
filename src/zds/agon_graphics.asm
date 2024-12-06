;
; Title:	BBC Basic for AGON - Graphics stuff
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
				
;			XDEF	CLG
;			XDEF	CLRSCN
			XDEF	MODE_
			XDEF	COLOUR_
;			XDEF	GCOL
;			XDEF	MOVE
;			XDEF	PLOT
;			XDEF	DRAW
			XDEF	POINT_
			XDEF	GETSCHR
			XDEF	GETSCHR_1
			
			XREF	ACCS
			XREF	OSWRCH
			XREF	ASC_TO_NUMBER
			XREF	EXTERR
			XREF	EXPRI
			XREF	COMMA
			XREF	XEQ
			XREF	NXT
			XREF	BRAKET
			XREF	CRTONULL
			XREF	NULLTOCR
			XREF	CRLF
			XREF	EXPR_W2
;			XREF	COUNT0
;			XREF	INKEY1
			
; CLG: clears the graphics area
;
;CLG:			VDU	10h
;			JP	XEQ

; CLS: clears the text area
;
;CLRSCN:		LD	A, 0Ch
;			JP	OSWRCH
				
; MODE n: Set video mode
;
MODE_:			PUSH	IX			; Get the system vars in IX
			MOSCALL	mos_sysvars		; Reset the semaphore
			RES.LIL	4, (IX+sysvar_vpd_pflags)
			CALL    EXPRI
			EXX
			VDU	16H			; Mode change
			VDU	L
			MOSCALL	mos_sysvars		
$$:			BIT.LIL	4, (IX+sysvar_vpd_pflags)
			JR	Z, $B			; Wait for the result			
			POP	IX
			JP	XEQ
			
; GET(x,y): Get the ASCII code of a character on screen
;
GETSCHR:		INC	IY
			CALL    EXPRI      		; Get X coordinate
			EXX
			PUSH	HL			; Stack X
			CALL	COMMA		
			CALL	EXPRI			; Get Y coordinate
			EXX 
			CALL	BRAKET			; Closing bracket	
			POP	DE			; Pop X back into DE
			CALL	GETSCHR_1
;			JP	INKEY1
	        	LD	DE,ACCS	
	                LD	(DE),A	
	                LD	A,80H	
        	        RET	NC	
	                INC	E	
                	RET	
;
; Fetch a character from the screen
; - DE: X coordinate
; - HL: Y coordinate
; Returns
; - A: The character or FFh if no match
; - F: C if match, otherwise NC
;
GETSCHR_1:		PUSH	IX			; Get the system vars in IX
			MOSCALL	mos_sysvars		; Reset the semaphore
			RES.LIL	1, (IX+sysvar_vpd_pflags)
			VDU	23
			VDU	0
			VDU	vdp_scrchar
			VDU	E 
			VDU	D 
			VDU	L 
			VDU	H 
$$:			BIT.LIL	1, (IX+sysvar_vpd_pflags)
			JR	Z, $B			; Wait for the result
			LD.LIL	A, (IX+sysvar_scrchar)	; Fetch the result in A
			OR	A			; Check for 00h
			SCF				; C = character map
			JR	NZ, $F			; We have a character, so skip next bit
			XOR	A			; Clear carry
$$:			POP	IX			
			RET 

; POINT(x,y): Get the pixel colour of a point on screen
;
POINT_:			CALL    EXPRI      		; Get X coordinate
			EXX
			LD	(VDU_BUFFER+0), HL
			CALL	COMMA		
			CALL	EXPRI			; Get Y coordinate
			EXX 
			LD	(VDU_BUFFER+2), HL
			CALL	BRAKET			; Closing bracket		
;
			PUSH	IX			; Get the system vars in IX
			MOSCALL	mos_sysvars		; Reset the semaphore
			RES.LIL	2, (IX+sysvar_vpd_pflags)
			VDU	23
			VDU	0
			VDU	vdp_scrpixel
			VDU	(VDU_BUFFER+0)
			VDU	(VDU_BUFFER+1)
			VDU	(VDU_BUFFER+2)
			VDU	(VDU_BUFFER+3)
$$:			BIT.LIL	2, (IX+sysvar_vpd_pflags)
			JR	Z, $B			; Wait for the result
;
; Return the data as a 1 byte index
;
			LD.LIL	L, (IX+(sysvar_scrpixelIndex))
			POP	IX	
;			JP	COUNT0
		        LD	H,0	
			EXX	
	                XOR	A	
                	LD	C,A		;INTEGER MARKER	
                	LD	H,A	
                	LD	L,A	
                	RET	

; COLOUR colour
; COLOUR L,P
; COLOUR L,R,G,B
;
COLOUR_:		CALL	EXPRI			; The colour / mode
			EXX
			LD	A, L 
			LD	(VDU_BUFFER+0), A	; Store first parameter
			CALL	NXT			; Are there any more parameters?
			CP	','
			JR	Z, COLOUR_1		; Yes, so we're doing a palette change next
;
			VDU	11h			; Just set the colour
			VDU	(VDU_BUFFER+0)
			JP	XEQ			
;
COLOUR_1:		CALL	COMMA
			CALL	EXPRI			; Parse R (OR P)
			EXX
			LD	A, L
			LD	(VDU_BUFFER+1), A
			CALL	NXT			; Are there any more parameters?
			CP	','
			JR	Z, COLOUR_2		; Yes, so we're doing COLOUR L,R,G,B
;
			VDU	13h			; VDU:COLOUR
			VDU	(VDU_BUFFER+0)		; Logical Colour
			VDU	(VDU_BUFFER+1)		; Palette Colour
			VDU	0			; RGB set to 0
			VDU	0
			VDU	0
			JP	XEQ
;
COLOUR_2:		CALL	COMMA
			CALL	EXPRI			; Parse G
			EXX
			LD	A, L
			LD	(VDU_BUFFER+2), A
			CALL	COMMA
			CALL	EXPRI			; Parse B
			EXX
			LD	A, L
			LD	(VDU_BUFFER+3), A							
			VDU	13h			; VDU:COLOUR
			VDU	(VDU_BUFFER+0)		; Logical Colour
			VDU	FFh			; Physical Colour (-1 for RGB mode)
			VDU	(VDU_BUFFER+1)		; R
			VDU	(VDU_BUFFER+2)		; G
			VDU	(VDU_BUFFER+3)		; B
			JP	XEQ

; GCOL mode,colour
;
;GCOL:			CALL	EXPRI			; Parse MODE
;			EXX
;			LD	A, L 
;			LD	(VDU_BUFFER+0), A	
;			CALL	COMMA
;
;			CALL	EXPRI			; Parse Colour
;			EXX
;			LD	A, L
;			LD	(VDU_BUFFER+1), A
;
;			VDU	12h			; VDU:GCOL
;			VDU	(VDU_BUFFER+0)		; Mode
;			VDU	(VDU_BUFFER+1)		; Colour
;			JP	XEQ
			
; PLOT mode,x,y
;
;PLOT:			CALL	EXPRI		; Parse mode
;			EXX					
;			PUSH	HL		; Push mode (L) onto stack
;			CALL	COMMA 	
;			CALL	EXPR_W2		; Parse X and Y
;			POP	BC		; Pop mode (C) off stack
;PLOT_1:		VDU	19H		; VDU code for PLOT				
;			VDU	C		;  C: Mode
;			VDU	E		; DE: X
;			VDU	D
;			VDU	L		; HL: Y
;			VDU	H
;			JP	XEQ

; MOVE x,y
;
;MOVE:			CALL	EXPR_W2		; Parse X and Y
;			LD	C, 04H		; Plot mode 04H (Move)
;			JR	PLOT_1		; Plot

; DRAW x1,y1
; DRAW x1,y1,x2,y2
;
;DRAW:			CALL	EXPR_W2		; Get X1 and Y1
;			CALL	NXT		; Are there any more parameters?
;			CP	','
;			LD	C, 05h		; Code for LINE
;			JR	NZ, PLOT_1	; No, so just do DRAW x1,y1
;			VDU	19h		; Move to the first coordinates
;			VDU	04h
;			VDU	E
;			VDU	D
;			VDU	L
;			VDU	H
;			CALL	COMMA
;			PUSH	BC
;			CALL	EXPR_W2		; Get X2 and Y2
;			POP	BC
;			JR	PLOT_1		; Now DRAW the line to those positions
			
			
			
