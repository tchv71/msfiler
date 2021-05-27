	MODULE	FDCNTR
; ----  CONTROLLER DEPENDENT SUBROUTINES  -------
; Version 1.1 for R86-rk  (c) TCHV 1991

;	27-Jan-1992  - Transparent error recovery
;	16-Feb-1992  - Debug error recovery

MaxTrying	equ	5; Maximum repeats of a command
Sector_Operation	equ	1
;	Debug		equ	1

; This module contains following procedures :
PUBLIC	HOME,POSIT,FD_WR_INIT,FD_RD_INIT,STPMTR,WT_END_CMD
PUBLIC	OPER,ChgDrive

EXTRN	BAD	; user hook if a bad sector detected
;-------------------------------------------------

	.8080
FDC_COM_STAT	EQU	0F700H
FDC_TRK		EQU	FDC_COM_STAT+1
FDC_SECT	EQU	FDC_COM_STAT+2
FDC_DATA	EQU	FDC_COM_STAT+3
FDC_CNTRL	EQU	FDC_COM_STAT+4
DMA		EQU	0F7E0H

; CHANGE CURRENT DRIVE Acc - Drive number (1-A,2-B)
; Returns Cy=0 - Ok, Cy=1 - Drive not ready
ChgDrive:
	push	psw
busy:	lda	FDC_Com_Stat
	ani	1
	jnz	busy
	pop	psw
	sta	drive	; to be extended
	call	Home	; Track is not remembered
	call	Wt_end_cmd
	call	Home
	ora	a
	ret

; SET THE HEAD TO TRACK 00
HOME:	MVI	A,8	; HOME & START MOTOR
	JMP	Start_Not_Sector_Operation

; STOP MOTOR & UNSELECT DRIVE
STPMTR:	ret
;	CALL	WT_END_CMD
;	XRA	A
;	STA	CNTRL
;	MVI	A,40H
;	CALL	STR_CMD
;	JMP	WT_END_CMD

; Start motor if it's not activated
Start_Motor:
	lda	FDC_COM_STAT
	ani	20h
	rnz
	lda	FDC_Trk
	sta	FDC_Data
	mvi	a,18h	; Start motor, Seek no check
	call	Start_Not_Sector_Operation
	jmp	WT_END_CMD

; SET HEAD TO DESIRED TRACK (ACC)
POSIT:	PUSH	PSW
	CALL	WT_END_CMD
	POP	PSW		; SET TRACK NO INTO
	STA	FDC_Data	; DATA REGISTER
	push	b
	mov	b,a
	lda	FDC_Trk
	cmp	b
	pop	b
	rz
	LDA	?40TRK
	ORA	A
	JZ	POSIT80
	MVI	A,14H	; Seek and Check command
	CALL	Start_Not_Sector_Operation
	CALL	Wait_no_check
	RZ
	LDA	?40TRK
	CMA
	STA	?40TRK
	LDA	FDC_Data
	PUSH	PSW
	CALL	HOME
	POP	PSW
	JMP	POSIT

POSIT80:PUSH	B
	LDA	FDC_Data
	PUSH	PSW
	ADD	A
	STA	FDC_Data
	LDA	FDC_Trk
	ADD	A
	STA	FDC_Trk
	MVI	A,18H	; Seek no check
	CALL	Start_Not_Sector_Operation
	call	WT_END_CMD
	POP	PSW
	STA	FDC_Trk
	STA	FDC_Data
	MVI	A,14H	; Seek and check
	POP	B
	JMP	Start_Not_Sector_Operation

;----------------------------------------------------
; WAIT FOR END OF PREVIOUS DISK COMMAND
;  Note: This subrotine exits only if no errors detected
WT_END_CMD:
	lda	Last_Operation_Kind
	ora	a	; ? Not_Sector_Operation
	jz	Simple_Wait
	CALL	Wait_no_check	; Wait for end of previous sector command
	jnz	Error_Detected
		mvi	a,MaxTrying	; Last attempt was succsessful,
		sta	TryCounter	; re-set trying counter
		RET

Error_Detected:	; Try again
	lda	TryCounter
	dcr	a
	jz	BAD	; All attempts are unsuccessfull
	sta	TryCounter
	call	Repeat_Command	; Try one more time
	jmp	WT_END_CMD

;--------------------------------------------------------
Simple_Wait:
	call	Wait_no_check
	jnz	Bad
	ret

Wait_no_check:
	LDA	WAIT_RQ	; IS WAITING NECESARRY ?
	ORA	A
	RZ
WT_EC:	LDA	FDC_Cntrl; WAIT FOR INRQ
	ANI	40H	;  SIGNAL
	JZ	WT_EC
	XRA	A
	STA	WAIT_RQ
	LDA	FDC_Com_Stat	; READ STATUS & CLEAR INRQ SIGNAL
	ANI	18H 		; CHECK ERROR BITS
	RET


	dseg
WAIT_RQ:db	0
?40TRK:	DB	0FFH
	cseg

; Repeat last controller command
Repeat_Command:
	push	h
	push	d
	push	b

ifdef	Debug
	mvi	c,7
	call	0f809h
endif
	lda	TryCounter
	cpi	2
	jnc	Simple_Repeat
	lda	FDC_Trk
	push	psw
	call	HOME
	pop	psw
	call	POSIT
Simple_Repeat:
	lhld	LastSize
	mov	b,h
	mov	c,l
	lhld	LastAddr
	xchg
	lhld	Last_SideSect
	lda	LastCommand
	call	FD_RW_COMMON
	pop	b
	pop	d
	pop	h
	ret

; INITIALISE SECTOR WRITING
;  In: H - side (0/0ffh) ; L - sector (0..)
FD_WR_INIT:
	LXI	B,4200H
	MVI	A,0A0H
	jmp	FD_RW_COMMON

; INITIALISE SECTOR READING
FD_RD_INIT:
	LXI	B,8200H
	MVI	A,80H
FD_RW_COMMON:
; PROGRAM DMA & DISK CONTROLLERS
OPER:
	push	psw
	call	WT_END_CMD
	pop	psw
	sta	LastCommand
	shld	Last_SideSect
	call	Start_Motor
	mov	a,l
	sta	FDC_Sect
	MVI	A,0A4H
	STA	DMA+8
	push	h
	LXI	H,DMA+2
	MOV	M,E
	MOV	M,D
	INX	H
	MOV	M,C
	MOV	M,B
	MVI	L,0E8H
	MVI	M,0B6H
	pop	h
	lda	LastCommand
	call	START_CMD
			; * Save information to
			; repeat command if necesarry
	shld	Last_SideSect
	xchg
	shld	LastAddr
	xchg
	mov	h,b
	mov	l,c
	shld	LastSize
			; *
	mvi	a,Sector_operation
	sta	Last_Operation_Kind
	MVI	A,0FFH
	STA	WAIT_RQ	; WAITING IS NECESARRY
	RET

; Start not sector operation
Start_Not_Sector_Operation:
	push	psw
	call	WT_END_CMD
	pop	psw
	push	h
	mvi	h,0
	call	START_CMD
	pop	h
	xra	a
	sta	Last_Operation_Kind
	mvi	a,0ffh
	sta	WAIT_RQ
	ret

START_CMD:
	PUSH	PSW
	mov	a,h	; 0 OR 0FFH
	ANI	10H
	ORI	20H	; HLD IMITATION & DRIVE 1 SELECT
	push	b
	mov	b,a
	lda	drive
	ora	b
	pop	b
	STA	FDC_Cntrl
	POP	PSW
	STA	FDC_COM_STAT
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
	ENDMODULE

; ---- MS-DOS  LOGICAL READING & WRITING ----------------
; Version 1.0				(c) TCHV 1991
	MODULE	LOGRW

PUBLIC  RdBoot,RD_FAT,WR_FAT,RD_CLST,WR_CLST,RD_SECT,WR_SECT

EXTRN	FATBUF	; adress of FAT buffer (512 bytes)

; from FDCNTRL
EXTRN	POSIT,FD_RD_INIT,FD_WR_INIT,WT_END_CMD,HOME

; C runtime library
EXTRN	?DVNHD,?mulhd,?neghl

	.8080
; Reads boot sector with disk parameter block
;
; NOTE: This routine MUST be called before all
; MS-DOS disk operations
RdBoot: call	Home	;  Only low level disk operations
			; are allowed here.
	lxi	h,0001h
	lxi	d,FATBUF
	call	FD_RD_INIT
	call	WT_END_CMD
	lxi	h,0bh	; Offset of DPB in boot sector
	dad	d
	lxi	d,ParamBlk
	mvi	b,19	; DPB length
cpy:	mov	a,m
	stax	d
	inx	h
	inx	d
	dcr	b
	jnz	cpy

	lhld	NumFats
	mvi	h,0
	xchg
	lhld	SctPerFat
	call	?mulhd
	xchg
	lhld	ResrvdSect
	dad	d
	shld	StrtDir

	push	h
	lhld	DirEntries
	lxi	d,32
	call	?mulhd
	xchg
	lhld	BytPerSect
	xchg
	call	?dvnhd
	mov	a,e
	ora	a
	jz	$+4
	inr	l
	shld	DirLen	; Dir length in sectors
	pop	d
	dad	d
	shld	FilesArea

	call	?neghl
	xchg
	lhld	TotSct
	dad	d
	lda	SctPerClst
	mov	e,a
	mvi	d,0
	call	?dvnhd
	shld	MaxClst##

	lhld	BytPerSect
	lxi	d,32
	call	?dvnhd
	shld	Entr_DS	; Number of entries per directory sect

	lhld	BytPerSect
	lda	SctPerClst
	mov	e,a
	mvi	d,0
	call	?mulhd
	shld	ClstSize
	ret

; READ THE FILE ALLOCATION TABLE
RD_FAT:	PUSH	H
	PUSH	D
	LXI	D,FATBUF
	lhld	ResrvdSect
	lda	SctPerFat
	mov	b,a
RdFat0:	call	Wt_End_Cmd
	call	Rd_Sect
	inx	h
	dcr	b
	jnz	RdFat0
	CALL	Wt_End_Cmd
	POP	D
	POP	H
	RET

; WRITE THE FILE ALLOCATION TABLE
WR_FAT:	PUSH	H
	lhld	ResrvdSect
	lda	NumFats
	mov	c,a
SavOneCopy:
	LXI	D,FATBUF
	lda	SctPerFat
	mov	b,a
SavSct:	CALL	WT_END_CMD
	call	WR_SECT
	inx	h
	dcr	b
	jnz	SavSct
	dcr	c
	jnz	SavOneCopy
	POP	H
	RET

; READ CLUSTER POINTED BY HL
; DE - BUFFER TO READ
RD_CLST:PUSH	H
	push	b
	CALL	CMP_SN
	lda	SctPerClst
	mov	b,a
@Rd_c:	CALL	RD_SECT
	INX	H
	dcr	b
	jnz	@Rd_c
	pop	b
	POP	H
	RET

; WRITE CLUSTER POINTED BY HL
WR_CLST:PUSH	H
	push	b
	CALL	CMP_SN
	lda	SctPerClst
	mov	b,a
@Wr_c:	CALL	WR_SECT
	INX	H
	dcr	b
	jnz	@Wr_c
	pop	b
	POP	H
	RET

; CALCULATE SECTOR NUMBER
CMP_SN:	push	d
	dcx	h
	dcx	h
	xchg
	lda	SctPerClst
	mov	l,a
	mvi	h,0
	call	?mulhd	; (ClstNum-2)*Sectors_Per_Cluster
	xchg
	lhld	FilesArea; The first sector of files area
	dad	d
	pop	d
	ret


; READ THE LOGICAL SECTOR
; HL - LOGICAL SECTOR NUMBER
; DE - BUFFER TO READ
RD_SECT:PUSH	H
	push	b
	CALL	SET_ADR
	CALL	FD_RD_INIT
RW_EXT:	lhld	BytPerSect
	DAD	D
	XCHG
	pop	b
	POP	H
	RET

; WRITE THE LOGICAL SECTOR
WR_SECT:PUSH	H
	push	b
	CALL	SET_ADR
	CALL	FD_WR_INIT
	JMP	RW_EXT


; SET TRACK, SECTOR & SIDE
; HL - LOGICAL SECTOR NUMBER
SET_ADR:PUSH	D
	push	h
	lhld	SctPerTrk
	xchg
	lhld	NumHeads
	call	?mulhd
	xchg
	pop	h
	CALL	?DVNHD   ; hl=SectNum/(NumHeads*SectPerTrk)
	lda	SctPerTrk; de=SectNum%(NumHeads*SectPerTrk)
	mov	b,a
	MOV	A,E
	sub	b	; NumHeads
	JC	SIDE_0
	MOV	E,A
	MVI	A,0FFH
	JMP	$+4
SIDE_0:	XRA	A
	PUSH	PSW
	MOV	A,L
	CALL	POSIT
	CALL	WT_END_CMD
	POP	PSW
	MOV	H,A
	MOV	L,E
	INR	L
	POP	D
	RET

	dseg
ParamBlk:
BtPrSc::
BytPerSect:	ds	2
SctPerClst::	ds	1
ResrvdSect:	ds	2
NumFats:	ds	1
DirEntries:	ds	2
TotSct:		ds	2
MediaDescr:	ds	1
SctPerFat:	ds	2
SctPerTrk:	ds	2
NumHeads:	ds	2
HidnSect:	ds	2
FilesArea::	ds	2
DirLen::	ds	2
Entr_Ds::	ds	2
StrtDir::	ds	2
ClstSize::	ds	2
	END

	ENDMODULE

;   ---- MS-DOS  FAT & DIR OPERATIONS ---
; Version 1.1			(c) TCHV,1991
;    last modified 26-oct-1991 12:50 am
	MODULE	FATDIR

; This module contains following procedures:
PUBLIC	GT_NFC,GET_FAT,FND_FREE,FIL_FAT ; FAT operations
PUBLIC	SRCH_F,SRCH_N,WR_DIR		; DIR operations

PUBLIC	DIR_ADR	; address of found dir entry

EXTRN	FATBUF,DIRBUF	; (512 bytes)

; from LOGRW and FDCNTRL modules
EXTRN	RD_SECT,WR_SECT,WT_END_CMD
EXTRN	SctPerClst

; C runtime library
EXTRN	?slhb,?srnhb,?neghl,?dvnhd


	.8080

; FIND FREE CLUSTER
;   HL - STARTING CLUSTER
; RETURNS: HL - FIRST FREE CLUSTER
;    CY=1 if there's no FREE clusters
FND_FREE:
FND_F:
	PUSH	H
	CALL	GET_FAT
	MOV	A,H
	ORA	L
	POP	H
	INX	H
	JNZ	FND_F
	DCX	H

	push	d	; Checking for existing of this cluster
	xchg
	lhld	MaxClst
	xchg
	inx	d	; CY=1 if FreeClst<=MaxClst
	call	?CDEHL
	cmc		; CY=1 if FreeClst>MaxClst
	pop	d
	RET

MaxClst::DW	354	; Here is the maximum cluster number on
			; volume

; Set flags according (HL-DE)
?CDEHL:	mov	a,h
	cmp	d
	rnz
	mov	a,l
	cmp	e
	ret


; FILLS FAT FIELD BY A GIVEN NUMBER
; HL - FAT FIELD NUMBER
; DE - VALUE TO WRITE
FIL_FAT:PUSH	H
	PUSH	D
	CALL	GT_ADR
	JC	FF1
	MOV	A,H
	ANI	0F0H
	ORA	D
	MOV	D,A
	LHLD	FAT_ADR
	MOV	M,E
	JMP	FF2

FF1:	XCHG
	MVI	B,4
	CALL	?slhb
	XCHG
	MOV	A,L
	ANI	0FH
	LHLD	FAT_ADR
	ORA	E
	MOV	M,A
FF2:	INX	H
	MOV	M,D
	POP	D
	POP	H
	RET

; GET NEXT FILE CLUSTER
; RETURNS: HL - NEXT FILE CLUSTER NUMBER
;          CF=1 - LAST CLUSTER OF FILE
GT_NFC:	CALL	GET_FAT
	MOV	A,H
	CPI	0FH
	JNZ	OK
	MOV	A,L
	CPI	0F8H
	JC	OK
	STC
	RET
OK:	ORA	A
	RET

; EXTRACTS FAT FIELD FOR A GIVEN NUMBER
; HL - FAT FIELD NUMBER
; RETURNS: HL - FAT FIELD
GET_FAT:CALL	GT_ADR
	JC	GTF1
	MOV	A,H
	ANI	0FH
	MOV	H,A
	RET
GTF1:	MVI	B,4
	jmp	?srnhb

GT_ADR:	PUSH	D
	MOV	D,H
	MOV	E,L
	DAD	H
	DAD	D
	MVI	B,1
	CALL	?srnhb
	PUSH	PSW
	LXI	D,FATBUF
	DAD	D
	SHLD	FAT_ADR
	MOV	E,M
	INX	H
	MOV	D,M
	XCHG
	POP	PSW
	POP	D
	RET

FAT_ADR:DS	2
CURC_R:	DS	2

EXTRN	Entr_DS,DirLen,StrtDir
; ----- DIRECTORY SEARCH ------
; SEARCH FIRST FILE OCCURENCE INTO DIRECTORY
; DE -FILE PATTERN
;    A=1 - STOP ON ERASED FILE
;    A=0 - DON'T STOP
SRCH_F:	STA	S_MODE
	XRA	A
	STA	DIR_SECT
NXT_SCT:XRA	A
	STA	DIR_ENT
	LXI	H,DIRBUF
	SHLD	DIR_ADR
	CALL	RD_DIR
CUR_SCT:PUSH	D
	CALL	CHK_ITM
	POP	D
	LHLD	DIR_ADR
	RZ
	RC
SRCH_N:	LHLD	DIR_ADR
	LXI	B,20H
	DAD	B
	SHLD	DIR_ADR
	lda	Entr_DS ; Entries per directory sector
	mov	b,a
	LDA	DIR_ENT
	INR	A
	STA	DIR_ENT
	cmp	b
	JNZ	CUR_SCT
	lda	DirLen	; Dir length in sectors
	mov	b,a
	LDA	DIR_SECT
	INR	A
	STA	DIR_SECT
	cmp	b
	jnz	NXT_SCT
	STC
	RET

S_MODE:	DS	1
; CHECK CURRENT ENTRY FOR FILE OCCURENCE
; DE - FILE PATTERN
CHK_ITM:LHLD	DIR_ADR
	INX	D
	MOV	A,M
	CPI	0E5H
	JZ	?FAIL
	ORA	A
	JZ	END_DIR
	MVI	C,11
CHKI:	LDAX	D
	INX	D
	CPI	'?'
	JZ	NXT_C
	CMP	M
	JNZ	FAIL
NXT_C:	INX	H
	DCR	C
	JNZ	CHKI
	XRA	A	; Z=1
	RET

?FAIL:	LDA	S_MODE
	ORA	A
	JNZ	END_DIR
FAIL:	XRA	A	; Z=0 C=0
	INR	A
	RET

END_DIR:XRA	A	; Z=0 C=1
	SUI	1
	RET

; READ CURRENT DIR SECTOR
RD_DIR:	PUSH	D
	CALL	GT_SCT
	CALL	RD_SECT
	CALL	WT_END_CMD
	POP	D
	RET

; WRITE CURRENT DIR SECTOR
WR_DIR:	PUSH	D
	CALL	GT_SCT
	CALL	WR_SECT
	CALL	WT_END_CMD
	POP	D
	RET

GT_SCT:	LDA	DIR_SECT
	MOV	L,A
	MVI	H,0
	xchg
	lhld	StrtDir
	dad	d
	LXI	D,DIRBUF
	RET


DIR_ENT:DS	1 ; CURRENT ENTRY NUMBER INTO DIR SECTOR
DIR_SECT:DS	1 ; CURRENT DIRECTORY SECTOR
DIR_ADR:DS	2 ; ADDRESS OF CURRENT DIR ENTRY
	END
	ENDMODULE

; ---- FILE READ, WRITE & ERASE OPERATIONS ---
	MODULE	FILOPR
; Version 1.1		(c) TCHV 1991
PUBLIC	VER,OPN_FIL,RD_REC,CRT_FIL,WR_REC,CLS_FIL,ERS_FIL

;       For this moment the module FILOPR allows you
; to open ONE file either for reading or for writing
; (but not both). You must CLOSE current file before
; processing  another one.  So you  can't open  more
; then 1 file at a moment.
;
;  You must read or write a records which size is
; equal to cluster size on volume (public variable
; ClstSize),but last record might be less.

; from LOGRW module
EXTRN	RD_FAT,WR_FAT,RD_CLST,WR_CLST,ClstSize
; from FATDIR module
EXTRN	SRCH_F,WR_DIR
EXTRN	DIR_ADR
EXTRN	GT_NFC,FND_FREE,FIL_FAT

VER	EQU	0102H

	.8080
GETW	MACRO
	MOV	E,M
	INX	H
	MOV	D,M
	INX	H
	XCHG
	ENDM

; OPEN FILE FOR READING
; DE - FILE PATTERN
; RETURNS CF=1 IF FILE NOT FOUND
;  HL - FIRST FILE CLUSTER
OPN_FIL:CALL	RD_FAT
	XRA	A
	CALL	SRCH_F
	RC	; FILE NOT FOUND
	LXI	B,1AH
	DAD	B
	GETW
	SHLD	CURC_R
	PUSH	H
	XCHG
	GETW
	SHLD	CURS_R
	POP	H
	ORA	A	; CLEAR CF
	RET

EXTRN	?dvnhd
; READ NEXT RECORD (1 CLUSTER)

; IN: DE - CLUSTER  BUFFER
; OUT: HL - NUMBER OF BYTES ACTUALLY READ
; CY=1 IF IT'S A LAST RECORD OF A FILE
RD_REC:	PUSH	D
	LHLD	CURC_R
	CALL	RD_CLST
	LHLD	CURC_R
	CALL	GT_NFC
	SHLD	CURC_R
	lhld	ClstSize
	POP	D
	RNC
	LHLD	CURS_R
	MOV	A,H
	ORA	L
	JZ	EXT
	push	d
	xchg
	lhld	ClstSize; File_Size mod Cluster_size
	xchg
	call    ?dvnhd
	xchg
	pop	d
	mov	a,h
	ora	l
	JNZ	EXT
	lhld	ClstSize
EXT:	STC
	RET


; CREATE FILE (DE - FILE PATTERN)
CRT_FIL:CALL	RD_FAT
	XRA	A
	CALL	SRCH_F
	JC	F_N_EX
	PUSH	D
	CALL	ERS_FIL
	POP	D
F_N_EX:	MVI	A,1
	CALL	SRCH_F
	INX	D
	MVI	C,11
CF0:	LDAX	D
	MOV	M,A
	INX	H
	INX	D
	DCR	C
	JNZ	CF0
	MVI	C,20H-11
CF1:	MVI	M,0
	INX	H
	DCR	C
	JNZ	CF1
	PUSH	H
	LXI	H,2
	CALL	FND_FREE
	XCHG
	POP	H
	RC
	LXI	B,-6
	DAD	B
	MOV	M,E
	INX	H
	MOV	M,D
	XCHG
	SHLD	CURC_W
	SHLD	OLDC_W
	CALL	WR_DIR
	LXI	H,0
	SHLD	SIZE_W
	XRA	A
	RET


; WRITE A RECORD (1 CLUSTER) TO
; A OPENED FILE
; DE - RECORD BUFFER
; HL - NUMBER OF BYTES TO WRITE (<>ClstSize FOR LAST RECORD)
WR_REC:	PUSH	H
	push	d
	XCHG
	LHLD	SIZE_W
	DAD	D
	SHLD	SIZE_W
	LHLD	CURC_W
	SHLD	OLDC_W
	pop	d
	CALL	WR_CLST
	PUSH	D
	PUSH	H
	INX	H
	CALL	FND_FREE
	XCHG
	POP	H
	CALL	FIL_FAT
	XCHG
	SHLD	CURC_W
	POP	D
	POP	H
	RET

; CLOSE OPENED FILE
CLS_FIL:LHLD	OLDC_W
	LXI	D,0FF9H
	CALL	FIL_FAT
	LHLD	DIR_ADR
	LXI	D,1CH
	DAD	D
	XCHG
	LHLD	SIZE_W
	XCHG
	MOV	M,E
	INX	H
	MOV	M,D
	CALL	WR_FAT
	CALL	WR_DIR
	RET

	DSEG
CURC_R:	DS	2
CURS_R:	DS	2
CURC_W:	DS	2
OLDC_W:	DS	2
SIZE_W:	DS	2
	CSEG

; ERASE FILE
; DE - FILE PATTERN
; RETURNS CF=1 IF FILE NOT FOUND
ERS_FIL:CALL	OPN_FIL
	RC
CL_CHN:	MOV	A,H
	ORA	L
	JZ	END_ERS
	push	h
	CALL	GT_NFC
	pop	d
	PUSH	PSW
	PUSH	H
	XCHG
	LXI	D,0
	CALL	FIL_FAT
	POP	H
	POP	PSW
	JNC	CL_CHN
END_ERS:LHLD	DIR_ADR
	MVI	M,0E5H
	CALL	WR_FAT
	CALL	WR_DIR
	XRA	A
	RET

	END

	ENDMODULE








	JNC	CL_CHN
END_ERS:LHLD	DIR_ADR
	MVI	M,0E5H
	CALL	WR_FAT
	CALL	WR_DIR
	XRA	A
	RET

	END

	ENDMODULE