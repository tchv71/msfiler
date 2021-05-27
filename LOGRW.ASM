
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

	END
