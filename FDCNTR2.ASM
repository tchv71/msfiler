;  FDCNTR.ASM - Controller dependent subroutines
;
; Version 2.0 for Sinclair Profi   (c) TCHV 1991-93

	.Z80
;	27-Jan-1992  - Transparent error recovery
;
; Adapted for Sinclair PROFI by MaxWolf
;       04-Jul-1992
;
;       11-Oct-1993  - Delete some errors found on RK-86 version

MaxTrying	equ	5; Maximum repeats of a command
Sector_Operation	equ	1
;	Debug		equ	1
;
; This module contains following procedures :
PUBLIC	HOME,POSIT,FD_WR_INIT,FD_RD_INIT,STPMTR,WT_END_CMD
PUBLIC	OPER,ChgDrive

EXTRN	BAD	; user hook if a bad sector detected
;-------------------------------------------------

FDC_COM_STAT	EQU	01fh
FDC_TRK		EQU	03fh
FDC_SECT	EQU	05fh
FDC_DATA	EQU	07fh
FDC_CNTRL	EQU	0bfh
DMA		EQU	0F7E0H

; CHANGE CURRENT DRIVE Acc - Drive number (1-A,2-B)
; Returns Cy=0 - Ok, Cy=1 - Drive not ready
ChgDrive:
	push	af
busy:	in	a,(FDC_Com_Stat)
	and	1
	jr	nz,busy
	pop	af
	ld	(drive),a; to be extended
	call	Home	; Track is not remembered
	call	Wt_end_cmd
	call	Home
	xor	a
	dec	a
			;       11-Oct-1993
	ld	(?40TRK),a
	or	a
	ret

; SET THE HEAD TO TRACK 00
HOME:	ld	a,8	; HOME & START MOTOR
	jp	Start_Not_Sector_Operation

; STOP MOTOR & UNSELECT DRIVE
STPMTR:	ret
;	CALL	WT_END_CMD
;	XRA	A
;	STA	CNTRL
;	MVI	A,40H
;	CALL	STR_CMD
;	jp	WT_END_CMD

ABRT_CMD::
	ld	a,0d0h
	out	(fdc_com_stat),a
	xor	a
	ld	(WAIT_RQ),A
	RET
	
; Start motor if it's not activated
Start_Motor:
	in	a,(FDC_COM_STAT)
	and	20h
	ret	nz
	in	a,(FDC_Trk)
	out	(FDC_Data),a
	ld	a,18h	; Start motor, Seek no check
	call	Start_Not_Sector_Operation
	jp	WT_END_CMD

; SET HEAD TO DESIRED TRACK (ACC)
POSIT:	push	af
	CALL	WT_END_CMD
	call	HOME
	call	WT_END_CMD
	pop	af		; SET TRACK NO INTO
	out	(FDC_Data),a	; DATA REGISTER
	push	bc
	ld	b,a
	in	a,(FDC_Trk)
	cp	b
	pop	bc
	ret	z
	ld	a,(?40TRK)
	OR	A
	Jr	Z,Double_Stepping
	ld	A,14H	; Seek and Check command
	CALL	Start_Not_Sector_Operation
	CALL	Wait_no_check
	and	18h
stp::	Ret	Z
	ld	a,(?40TRK)
	cpl
	ld	(?40TRK),a
	in	a,(FDC_Data)
	push	af
	CALL	HOME
	pop	af
	jp	POSIT

Double_stepping:
	PUSH	Bc
	in	a,(FDC_Data)
	push	af
	ADD	A,a
	out	(FDC_Data),a
	in	a,(FDC_Trk)
	ADD	A,a
	out	(FDC_Trk),a
	ld	A,18H	; Seek no check
	CALL	Start_Not_Sector_Operation
	call	WT_END_CMD
	pop	af
	out	(FDC_Trk),a
	out	(FDC_Data),a
	ld	A,14H	; Seek and check
	POP	Bc
	jp	Start_Not_Sector_Operation

;----------------------------------------------------
; WAIT FOR END OF PREVIOUS DISK COMMAND
;  Note: This subrotine exits only if no errors detected
;        else it jumps to BAD
;
WT_END_CMD:
	ld	a,(Last_Operation_Kind)
	or	a	; ? Not_Sector_Operation
	jr	z,Simple_Wait
	CALL	Wait_no_check	; Wait for end of previous sector command
	and	7ch
	jr	nz,Error_Detected
		ld	a,MaxTrying	; Last attempt was succsessful,
		ld	(TryCounter),a	; re-set trying counter
		RET

Error_Detected:	; Try again
	ld	a,(TryCounter)
	dec	a
	jp	z,BAD	; All attempts are unsuccessfull
	ld	(TryCounter),a
	call	Repeat_Command	; Try one more time
	jp	WT_END_CMD

;--------------------------------------------------------
Simple_Wait:
	call	Wait_no_check
	and	18h
	ret	z
	ld	a,MaxTrying
	ld	(TryCounter),a
	jp	Bad

Wait_no_check:
	ld	a,(WAIT_RQ)	; IS WAITING NECESARRY ?
	OR	A
	Ret	Z
WT_EC:	in	a,(FDC_Cntrl); WAIT FOR INRQ
	ANd	80H	;  SIGNAL
	Jr	Z,WT_EC
	xor	A
	ld	(WAIT_RQ),a
	in	a,(FDC_Com_Stat); READ STATUS & CLEAR INRQ SIGNAL
;	and	18h 		; CHECK ERROR BITS
	RET


	dseg
WAIT_RQ:db	0
?40TRK:	DB	0FFH
	cseg

; Repeat last controller command
Repeat_Command:
	push	hl
	push	de
	push	bc

if 0
	ld	a,(TryCounter)
	cp	3
	jr	nc,Simple_Repeat
endif
	ld	a,(TryCounter)
	PUSH	AF
		XoR	a
		ld	(Last_Operation_Kind),a
	in	a,(FDC_Trk)
	push	af
	call	HOME
	pop	af
	call	POSIT
	pop	af
	ld	(TryCounter),a
Simple_Repeat:
	ld	bc,(LastSize)
	ld	hl,(LastAddr)
	ex	de,hl
	ld	hl,(Last_SideSect)
	ld	a,(LastCommand)
	call	FD_RW_COMMON
	pop	bc
	pop	de
	pop	hl
	ret

; INITIALISE SECTOR WRITING
;  In: H - side (0/0ffh) ; L - sector (0..)
FD_WR_INIT:
	Ld	Bc,0100H
	ld	A,0A4H
	jp	FD_RW_COMMON

; INITIALISE SECTOR READING
FD_RD_INIT:
	Ld	Bc,0000H
	ld	A,84H
FD_RW_COMMON:
; PROGRAM DMA & DISK CONTROLLERS
OPER:
	push	af
	call	WT_END_CMD
	pop	af
	ld	(LastCommand),a
	ld	(Last_SideSect),hl
	ld	(LastAddr),de
	ld	(LastSize),bc
	call	Start_Motor
	ld	a,l
	out	(FDC_Sect),a
	ld	a,Sector_operation
	ld	(Last_Operation_Kind),a
	ld	A,0FFH
	ld	(WAIT_RQ),a	; WAITING IS NECESARRY
	ld	a,(LastCommand)
	di
	call	START_CMD
	ex	de,hl
	dec	b
	ld	bc,FDC_Data
	jr	z,wop
rop:	in	a,(FDC_Cntrl)
	add	a,a
	jr	c,done
	jp	p,rop
	ini
	jr	rop
wop:	in	a,(FDC_Cntrl)
	add	a,a
	jr	c,done
	jp	p,wop
	outi
	jr	wop
done:	ei
	ex	de,hl
	ld	de,(LastAddr)
	ret
;
; Start not sector operation
Start_Not_Sector_Operation:
	push	af
	call	WT_END_CMD
	pop	af
	push	hl
	ld	h,0
	call	START_CMD
	pop	hl
	xor	a
	ld	(Last_Operation_Kind),a
	ld	a,0ffh
	ld	(WAIT_RQ),a
	ret

START_CMD:
	push	af
	ld	a,h	; 0 OR 0FFH - side
	ANd	10H
	xor	10h
	OR	0cH	; HLD IMITATION & DRIVE 1 SELECT
	push	bc
	ld	b,a
	ld	a,(drive)
	dec	a
	or	b
	pop	bc
	out	(FDC_Cntrl),a
	pop	af
	out	(FDC_COM_STAT),a
	ret


	dseg
DRIVE:	DB	1
Last_Operation_Kind:	db	0
Last_SideSect:	ds	2
LastCommand:	ds	1
LastAddr:	ds	2
LastSize:	ds	2
TryCounter:	db	MaxTrying
	END
