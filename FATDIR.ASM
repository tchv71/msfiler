
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

