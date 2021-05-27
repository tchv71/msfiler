;****** MF.ASM -  CP/M - MS-DOS filer**
;* V1.3            (C) TCHV, 1991-93  *
;* 11-Jul-1993                5:13 pm *
;**************************************

PROFI	equ	1

INCLUDE		SYSCALLS.MAC

;	 4-Mar-1992 - add wildcard support
;	10-Apr-1992 - debug wildcards
;       xx-xxx-1992 - debug memory allocation
;	08-Oct-1992 - add some features
;	11-Jul-1993 -

; Externally allocated memory
	extrn	FatBuf,RamStart,Stack

fcb1		equ	5ch


Max_CPM_Files	equ	64	; Maximum files got by SEARCH NEXT
MaxDrive	equ	'E'	; Maximum CPM drive

stksize		equ	80h
RamTop		equ	6
MaxRecSize	equ	1024
CmdLine		equ	81h

; ------ MS-DOS FILE OPERATIONS -----------
EXTRN	OPN_FIL,RD_REC,CRT_FIL,WR_REC,CLS_FIL,ERS_FIL
EXTRN	RD_FAT,PR_DIR,ClstSize
EXTRN	SRCH_F,SRCH_N

EXTRN	HOME,WT_END_CMD,ChgDrive,RdBoot
EXTRN	FD_RD_INIT

EXTRN	getstr,parsfn

extrn	?neghl

PUBLIC	BAD

; Export for PRDIR module
PUBLIC	PRNT

COMLEN		equ	80h
COMLIN		equ	81h

GET_COMLIN	macro
	lxi	h,COMLIN
	push	h
		lda	COMLEN
		add	l
		mov	l,a
		mvi	m,0
	pop	h
	endm


	.8080
STRT:
if PROFI
	MVI	A,'E'-'A'+1
	STA	Default_CPM_Drive
        sta	RAM_DISK
else
	MVI	A,'B'-'A'+1
	STA	Default_CPM_Drive
        sta	RAM_DISK
	LDA	2
	CPI	0DAH
	JZ	$+8
	MVI	A,'C'-'A'+1
        sta	RAM_DISK
	STA	Default_CPM_Drive
endif
	CALL	PRNT
	DB	10,13
DB 'Cpm - MS-DOS  Filer V1.3,11-Jul-1993              (C) Tchv, 1991-93',10,13,0

; RamEnd=RamStart+(RamTop-RamStart)&(-MaxRecSize)
	lhld	RamTop
	lxi	d,RamStart
	lxi	b,-MaxRecSize
	mov	a,l
	sub	e
	push	psw
	ana	c
	mov	l,a
	pop	psw
	mov	a,h
	sbb	d
	ana	b
	mov	h,a
	dad	d
	shld	RamEnd
;

	lxi	h,0
	dad	sp
	shld	oldsp
	lxi	sp,Stack+StkSize


	lda	FCB1+1
	lxi	h,CmdLine
	cpi	20h
	jnz	@do_command
; It's nothing to do (command line is empty)
	call	Print_Instructions
@do_loop:
	call	prnt
	db	10,13,0
	lda	Default_CPM_Drive
	adi	'A'-1
	call	putch
	call	prnt
	db	':*',0
	lxi	d,command_string
	call	getstr
        call	do_cmd
	jmp	@do_loop

@do_command:

	GET_COMLIN
	call	Do_Cmd
	jmp	exit


isspace:
	cpi	20h
	rz
	cpi	9
	ret

SkipSpaces:
	mov	a,m
	call	isspace
	rnz
	inx	h
	jmp	SkipSpaces

;----------------------------
Do_Cmd:
	call	SkipSpaces
	mov	a,m
	call	UpCase
	inx	h
	ora	a
	rz
	cpi	'@'
	jz	chg_drive
	push	psw
	call	SkipSpaces
	shld	CmdPos
	pop	psw
	CALL	UpCase
	CPI	'D'
	jz	dir_pr
	cpi	'R'
	jz	read_f
	cpi	'W'
	jz	write_f
	cpi	'E'
	jz	ers_f
	cpi	'K'
	jz	kill_f
	cpi	'X'
	jz	exit
	jmp	Print_Instructions


; Select last drive if needed
;  Returns: CY=1 if errors detected
SelDrive:
	sta	MS_Drive
	lxi	h,Last_Drive
	cmp	m
	jz	Nxt00

	sta	Last_Drive
	ora	a
	jz	Nxt00

	CALL	ChgDrive
	jnc	nxt00
	call	prnt
	db	10,13,'Drive not ready',0
	stc
	ret

DSK_SEL:
	ldax	d
	push	d
		call	SelDrive
	pop	d
	ret

NXT00:	CALL	HOME
	CALL	WT_END_CMD
	CALL	HOME
TRY_MS:	CALL	RdBoot
	LDA	FATBUF
	CPI	0e9h
	jz	nextd
	cpi	0ebh
	jz	nextd
	CALL	PRNT
	DB	10,13,'Insert MS-DOS disk & strike a key',0
	CALL	getch
	cpi	3
	stc
	rz
	JMP	TRY_MS
nextd:	CALL	RD_FAT
	xra	a
	ret

Print_Instructions:
	CALL	PRNT
	db	10,13,'MF2 action [[Drive:]file_pattern] '

	db	10,10,13,' Valid actions are :'
	db	10,13,9,9,'d - print the directory of MS-DOS disk'
	db	10,13,9,9,'r - read  file(s) from MS-DOS disk'
	db	10,13,9,9,'w - write file(s) to MS-DOS disk'
	db	10,13,9,9,'e - erase file(s) on MS-DOS disk'
	db	10,13,9,9,'k - kill file(s)  on CP/M disk'
	db	10,13,9,9,'x - exit to CP/M'
	db	10,13,9,9,'@D - change default CP/M drive to D',0
	ret


Copy_Fcb:
	lxi	d,cpmfcb
	lda	Default_CPM_Drive
	stax	d
	inx	d
	mvi	c,11
	mov	a,m
	stax	d
	inx	h
	inx	d
	dcr	c
	jnz	$-5
	mvi	c,36-12
	xra	a
	stax	d
	inx	d
	dcr	c
	jnz	$-3
	ret

; Basic MS Filer actions

; Usefull subroutines
SkipToNext:
	lhld	CmdPos
	call	SkipSpaces
	mov	a,m
	ora	a
	stc
	rz
	shld	CmdPos
	ora	a
	ret

CmdPtrToNext:
	lhld	CmdPos
@@skip:	inx	h
	mov	a,m
	ora	a
	stc
	rz
	call	isspace
	jnz	@@skip
	shld	CmdPos
	ora	a
	ret



;*	*	*	*	*	*
dir_pr::
	mov	a,m
	ora	a
	lxi	d,allfils
	jz	@dir

dr_pr:	call	SkipToNext
	lxi	d,FCB1
	call	parsfn
	inx	d
	ldax	d
	dcx	d
	cpi	20h
	jnz	@dir
	ldax	d
	lxi	d,allfils
	stax	d

@dir:	call	DSK_SEL
	rc
	push	d
		call	prnt
		db	10,13,0
	pop	d
	call	PR_DIR
	call	CmdPtrToNext
	jnz	dr_pr
	ret


allfils:db	0,'???????????'

;*	*	*	*	*	*
read_f::
	call	SkipToNext
	rc
	lxi	d,fcb1
	push	d
	call	parsfn
	pop	d

	call	DSK_SEL
	rc
	XRA	A
	CALL	SRCH_F
	jc	FNF
	call	@read_f
	rc
@LP:	lxi	d,fcb1
	call	SRCH_N
	jc	rd_f@@
	call	@read_f
	jnc	@LP
	ret

rd_f@@:	call	CmdPtrToNext
	jnc	read_f
	ret

@read_f::
	push	h
	call	Copy_Fcb
	pop	h
	call	OPN_FIL
	lxi	d,cpmfcb
	call	PRNT_FN
        call	selCPM
	SYSCALL	@delete	; Delete file
	LXI	D,cpmfcb
	SYSCALL	@create	; Create file
	inr	a
	jz	DIROWF

RDF0:	call	selMSDOS
	lxi	d,RamStart
	call	Rd_From_MS
	push	psw
	call	Wt_End_Cmd
	call	selCPM
	call	Wr_To_CPM
	jc	Wrt_Err
	pop	psw
	jnc	RDF0
	LXI	D,cpmfcb
	SYSCALL	@close
        xra	a
	call	selMSDOS
	ret
Wrt_Err:
	pop	psw
	call	prnt
	db	13,10,'? CP/M write error (Disk full)',0
	stc
	ret


; *	*       *	*	*	*
write_f::
	call	SkipToNext
	lxi	d,fcb1
	call	parsfn

	lxi	d,80h
	syscall	@setdma

	lxi	d,fcb1
	ldax	d
	sta	MS_Drive

	lda	Default_CPM_Drive
	stax	d

	lxi	h,Entrs_List
	shld	Entry_Ptr

        call	selCPM
	syscall	@search_first
	inr	a
	jz	FNF
	call	Save_entry
@wr_loop:
	lxi	d,fcb1
	syscall	@search_next
	inr	a
	jz	wrt_f00
	call	Save_Entry
	jmp	@wr_loop

wrt_f00:
	lxi	h,Entrs_List
wrt_one_file:
	mov	a,m
	ora	a
	jz	wrt_f01
	call	Copy_FCB
	push	h
		call	@write_f
	pop	h
	rc
	jmp	wrt_one_file

wrt_f01:
	call	CmdPtrToNext
	jnc	write_f
	ret


Save_Entry:
	lxi	h,80h
	lxi	b,20h
@loop:	dcr	a
	jz	@ext
	dad	b
	jmp	@loop
@ext:	inx	h
	xchg
	lhld	Entry_Ptr
	mvi	c,11
	ldax	d
	mov	m,a
	inx	h
	inx	d
	dcr	c
	jnz	$-5
	mvi	m,0
	shld	Entry_Ptr
	ret

@write_f::
;	lda	MS_Drive
;	call	SelDrive
;	rc
	lxi	d,cpmfcb
	call	PRNT_FN
	call	selCPM
	syscall	@open	; Open file
	inr	a
	jz	FNF

	lxi	d,cpmfcb
	call	CRT_FIL
	jc	DIROWF

wrf0:	lxi	d,RamStart
	call	selCPM
	call	Rd_From_Cpm
	push	psw
	call	selMSDOS
	call	Wr_To_MS
	jc	MS_DOS_Wrt_Err
	call	WT_END_CMD
	pop	psw
        jnc	wrf0
	call	CLS_FIL
	call	WT_END_CMD
	call	prnt
	db	9,'Ok',0
	ora	a
	ret

MS_DOS_Wrt_Err:
	pop	psw
	call	prnt
	db	13,10,'? MS-DOS write error (Disk full)',0
	stc
	ret

; *	*       *	*	*	*
ers_f:
	call	SkipToNext
	rc
	call	@ers_f
	call	CmdPtrToNext
	jnc	ers_f
	ret


@ers_f:
	lxi	d,fcb1
	call	parsfn
	call	DSK_SEL
	rc

	xra	a
	call	SRCH_F
	rc
	push	h
	pop	d
	dcx	d
	push	h
	call	PRNT_FN
	pop	h
	call	ERS_FIL
@ers_lp:
	lxi	d,fcb1
	call	SRCH_N
	rc
	push	h
	pop	d
	dcx	d
	push	h
	call	PRNT_FN
	pop	h
	call	ERS_FIL
	jmp	@ers_lp


; *	*       *	*	*	*
kill_f:	call	SkipToNext
	rc
	lxi	d,cpmfcb
	push	d
		call	parsfn
	pop	d
	call	selCPM

@del_again:
	push	d
        	syscall	13h
	pop	d
        inr	a
	jnz	@del_again
	call	CmdPtrToNext
	jnc	kill_f
	ret

;----------------------------------------------------------------------------
chg_drive:
	mov	a,m
	call	UpCase
	cpi	'A'
	rc
	cpi	MaxDrive+1
	rnc
	sui	'A'-1
	sta	Default_CPM_Drive
	ret

;---------------------------------------------------------------------------


;	**** Basic reading procedures ****

; Read as more as possible from CPM file
Rd_From_CPM:
	lxi	h,cpmfcb
	shld	CurFCB
	lxi	h,Rd_CPM_Rec
	shld	Rd_XX_Rec+1
	lxi	h,128
	jmp	RdIntoRam

;  HL - length of information have been read
;  cy=1 - it's a last portion of information
Rd_From_MS:
	lxi	h,Rd_MS_Rec
	shld	Rd_XX_Rec+1
	lhld	ClstSize

; Reading into memory using procedure Rd_XX_Rec
RdIntoRam:
	shld	RecSize
	lxi	h,RamStart
	shld	CurPos
	xchg
	lxi	h,0
	shld	RdSize
@RdIR:	call	Rd_XX_Rec
	push	psw
	xchg
	lhld	RdSize
	dad	d
	shld	RdSize
	pop	psw
	jc	@last_r

	lhld	RecSize
	xchg
	lhld	CurPos
	dad	d
	shld	CurPos

	xchg
	lhld	RamEnd
	call	?cdehl
	jnz	@RdIR
	ora	a
@last_r:lhld	RdSize
	ret

Rd_XX_Rec:
	jmp	0


;*** Read next MS-DOS record ***
Rd_MS_Rec:
	jmp	Rd_Rec


;*** Read next CPM record ***
;   DE - RAM address to read
;   (CurFCB) - FCB for current file
; Returns:
;     HL - number of bytes actually read.
Rd_CPM_Rec:
	push	b
	push	d
	syscall	1ah
	lhld	CurFCB
	xchg
	syscall	@seqread
	lxi	h,128
	ora	a
	jz	NotEof
	stc
	lxi	h,0
NotEof:	pop	d
	pop	b
	ret

;		**** END ****

;	**** Basic writing procedures ****

; Write HL bytes to MS-DOS file
; cy = 1 if any writing errors occurs
Wr_To_MS:
	push	h
	lhld	ClstSize
	shld	RecSize
	lxi	h,Wr_MS_Rec
	jmp	WrFromRam

Wr_To_CPM:
	push	h
	lxi	h,CpmFcb
	shld	CurFCB
	lxi	h,128
	shld	RecSize
	lxi	h,Wr_CPM_Rec
WrFromRam:
	shld	Wr_XX_Rec+1
	pop	h
	shld	Bytes_To_Write
	lxi	h,RamStart
	shld	Write_Ptr
WrLoop:	lhld	Bytes_To_Write
	xchg
	lhld	RecSize
	call	?cdehl
	jc	Write_Last_Rec
	xchg
	lhld	Write_Ptr
	xchg
        push	h
	push	d
	call	Wr_XX_Rec
	pop	d
	pop	h
	rc
	dad	d
	shld	Write_Ptr
	lhld	RecSize
	call	?neghl
	xchg
	lhld	Bytes_To_Write
	dad	d
	shld	Bytes_To_Write
	jmp	WrLoop

Write_Last_Rec:
	mov	a,d
	ora	e
	rz
	lhld	Write_ptr
	xchg
Wr_XX_Rec:
	jmp	0

Wr_MS_Rec:
	jmp	Wr_Rec

Wr_CPM_Rec:
	syscall	1ah
	lhld	CurFcb
	xchg
	syscall	@seqwrt
	ora	a
	rz
	stc
	ret

	dseg
;  Different variables shared same memory
; because they are never used at the same time
Write_Ptr:
CurPos:	ds	2
Bytes_To_Write:
RdSize:	ds	2
RamEnd:	ds	2
CurFCB:	ds	2
RecSize:ds	2
	cseg
;	**** END ****

; Some different usefull subrotines
?cdehl:	mov	a,d
	cmp	h
	rnz
	mov	a,e
	cmp	l
	ret

UpCase:	cpi	60h
	rc
	sui	20h
	ret

getch:	mvi	e,0ffh
	syscall	6
	ora	a
	jz	getch
	ret

putch:	push	d
	push	b
	mov	e,a
	syscall	2
	pop	b
	pop	d
	ret

print_n:ldax	d
	inx	d
	call	putch
	dcr	c
	jnz	print_n
	ret

PRNT_FN:
	push	d
	push	d
	call	prnt	; Print copying file name
	db	10,13,9,0
  	pop	d

	inx	d
	mvi	c,8
	call	print_n
	mvi	a,'.'
	call	putch
	mvi	c,3
	call	print_n
	pop	d
	ret


PRNT:	POP	H
prnt1:	mov	e,m
	inx	h
	inr	e
	dcr	e
	jz	prnt2
	push	h
	syscall	2
	pop	h
	jmp	prnt1

prnt2:	PCHL

;**** Error handling procedures ****
DIROWF:
	call	prnt
	db	10,13,'? No directory space',0
	stc
	ret

EXIT:
if	0
	call	selCPM
	mvi	a,1
	call	ChgDrive
	lhld	oldsp
	sphl
	ret
else
	mvi	a,1
	call	ChgDrive
	jmp	0
endif


FNF:	CALL	PRNT
	DB	'     ? File not found',0
	stc
	ret

BAD:	CALL	PRNT
	DB	10,13,'? Bad sector or disk not formatted',0
	JMP	EXIT

selMSDOS:
	lda	MS_Drive
	ora	a
	jnz	ChgDrive
	inr	a
	call	ChgDrive
	ret

selCPM: push	b
	push	d
	push	h
	lda	Default_CPM_Drive
	mvi	b,1
	mov	c,a
	lda	RAM_DISK
	cmp	C
	jz	sCPM1	; Don't need to check for ramdisk
	mov	a,c
	cpi	1	; if 'A' or 'D' => disk 1
	jz	sCPM0
	cpi	4
	jz	sCPM0
	mvi	b,2	; else => disk2
sCPM0:	mov	a,b
	call	ChgDrive
;	jc	DriveNotReady
sCPM2:	call	RdBoot
        lda	FATBUF
	cpi	0e9h
	jz	sCPM3
	cpi	0ebh
	jnz	sCPM1
sCPM3:	call	prnt
	db	13,10,'Insert CP/M disk & press a key',0
	call	getch
	jmp	sCPM0
sCPM1:	pop	h
	pop	d
	pop	b
	ret

	dseg
oldsp:	ds	2
tst_buf:ds	512
	cseg

cpmfcb:	rept	36/2
	dw	0
	endm


Entry_Ptr:	ds	2
Entrs_List:
	ds	11*Max_CPM_Files+1

Default_CPM_Drive:
		db	2
CmdPos:		ds	2
command_string:	db	80,0
		ds	80
Last_Drive:	db	0ffh
MS_Drive:	ds	1
RAM_DISK:	ds	1
	end	strt

;$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$



;****** MF.ASM -  CP/M - MS-DOS filer**
;* V1.3            (C) TCHV, 1991-93  *
;* 11-Jul-1993                5:13 pm *
;**************************************

PROFI	equ	1

INCLUDE		SYSCALLS.MAC

;	 4-Mar-1992 - add wildcard support
;	10-Apr-1992 - debug wildcards
;       xx-xxx-1992 - debug memory allocation
;	08-Oct-1992 - add some features
;	11-Jul-1993 -

; Externally allocated memory
	extrn	FatBuf,RamStart,Stack

fcb1		equ	5ch


Max_CPM_Files	equ	64	; Maximum files got by SEARCH NEXT
MaxDrive	equ	'E'	; Maximum CPM drive

stksize		equ	80h
RamTop		equ	6
MaxRecSize	equ	1024
CmdLine		equ	81h

; ------ MS-DOS FILE OPERATIONS -----------
EXTRN	OPN_FIL,RD_REC,CRT_FIL,WR_REC,CLS_FIL,ERS_FIL
EXTRN	RD_FAT,PR_DIR,ClstSize
EXTRN	SRCH_F,SRCH_N

EXTRN	HOME,WT_END_CMD,ChgDrive,RdBoot
EXTRN	FD_RD_INIT

EXTRN	getstr,parsfn

extrn	?neghl

PUBLIC	BAD

; Export for PRDIR module
PUBLIC	PRNT

COMLEN		equ	80h
COMLIN		equ	81h

GET_COMLIN	macro
	lxi	h,COMLIN
	push	h
		lda	COMLEN
		add	l
		mov	l,a
		mvi	m,0
	pop	h
	endm


	.8080
STRT:
if PROFI
	MVI	A,'E'-'A'+1
	STA	Default_CPM_Drive
        sta	RAM_DISK
else
	MVI	A,'B'-'A'+1
	STA	Default_CPM_Drive
        sta	RAM_DISK
	LDA	2
	CPI	0DAH
	JZ	$+8
	MVI	A,'C'-'A'+1
        sta	RAM_DISK
	STA	Default_CPM_Drive
endif
	CALL	PRNT
	DB	10,13
DB 'Cpm - MS-DOS  Filer V1.3,11-Jul-1993              (C) Tchv, 1991-93',10,13,0

; RamEnd=RamStart+(RamTop-RamStart)&(-MaxRecSize)
	lhld	RamTop
	lxi	d,RamStart
	lxi	b,-MaxRecSize
	mov	a,l
	sub	e
	push	psw
	ana	c
	mov	l,a
	pop	psw
	mov	a,h
	sbb	d
	ana	b
	mov	h,a
	dad	d
	shld	RamEnd
;

	lxi	h,0
	dad	sp
	shld	oldsp
	lxi	sp,Stack+StkSize


	lda	FCB1+1
	lxi	h,CmdLine
	cpi	20h
	jnz	@do_command
; It's nothing to do (command line is empty)
	call	Print_Instructions
@do_loop:
	call	prnt
	db	10,13,0
	lda	Default_CPM_Drive
	adi	'A'-1
	call	putch
	call	prnt
	db	':*',0
	lxi	d,command_string
	call	getstr
        call	do_cmd
	jmp	@do_loop

@do_command:

	GET_COMLIN
	call	Do_Cmd
	jmp	exit


isspace:
	cpi	20h
	rz
	cpi	9
	ret

SkipSpaces:
	mov	a,m
	call	isspace
	rnz
	inx	h
	jmp	SkipSpaces

;----------------------------
Do_Cmd:
	call	SkipSpaces
	mov	a,m
	call	UpCase
	inx	h
	ora	a
	rz
	cpi	'@'
	jz	chg_drive
	push	psw
	call	SkipSpaces
	shld	CmdPos
	pop	psw
	CALL	UpCase
	CPI	'D'
	jz	dir_pr
	cpi	'R'
	jz	read_f
	cpi	'W'
	jz	write_f
	cpi	'E'
	jz	ers_f
	cpi	'K'
	jz	kill_f
	cpi	'X'
	jz	exit
	jmp	Print_Instructions


; Select last drive if needed
;  Returns: CY=1 if errors detected
SelDrive:
	sta	MS_Drive
	lxi	h,Last_Drive
	cmp	m
	jz	Nxt00

	sta	Last_Drive
	ora	a
	jz	Nxt00

	CALL	ChgDrive
	jnc	nxt00
	call	prnt
	db	10,13,'Drive not ready',0
	stc
	ret

DSK_SEL:
	ldax	d
	push	d
		call	SelDrive
	pop	d
	ret

NXT00:	CALL	HOME
	CALL	WT_END_CMD
	CALL	HOME
TRY_MS:	CALL	RdBoot
	LDA	FATBUF
	CPI	0e9h
	jz	nextd
	cpi	0ebh
	jz	nextd
	CALL	PRNT
	DB	10,13,'Insert MS-DOS disk & strike a key',0
	CALL	getch
	cpi	3
	stc
	rz
	JMP	TRY_MS
nextd:	CALL	RD_FAT
	xra	a
	ret

Print_Instructions:
	CALL	PRNT
	db	10,13,'MF2 action [[Drive:]file_pattern] '

	db	10,10,13,' Valid actions are :'
	db	10,13,9,9,'d - print the directory of MS-DOS disk'
	db	10,13,9,9,'r - read  file(s) from MS-DOS disk'
	db	10,13,9,9,'w - write file(s) to MS-DOS disk'
	db	10,13,9,9,'e - erase file(s) on MS-DOS disk'
	db	10,13,9,9,'k - kill file(s)  on CP/M disk'
	db	10,13,9,9,'x - exit to CP/M'
	db	10,13,9,9,'@D - change default CP/M drive to D',0
	ret


Copy_Fcb:
	lxi	d,cpmfcb
	lda	Default_CPM_Drive
	stax	d
	inx	d
	mvi	c,11
	mov	a,m
	stax	d
	inx	h
	inx	d
	dcr	c
	jnz	$-5
	mvi	c,36-12
	xra	a
	stax	d
	inx	d
	dcr	c
	jnz	$-3
	ret

; Basic MS Filer actions

; Usefull subroutines
SkipToNext:
	lhld	CmdPos
	call	SkipSpaces
	mov	a,m
	ora	a
	stc
	rz
	shld	CmdPos
	ora	a
	ret

CmdPtrToNext:
	lhld	CmdPos
@@skip:	inx	h
	mov	a,m
	ora	a
	stc
	rz
	call	isspace
	jnz	@@skip
	shld	CmdPos
	ora	a
	ret



;*	*	*	*	*	*
dir_pr::
	mov	a,m
	ora	a
	lxi	d,allfils
	jz	@dir

dr_pr:	call	SkipToNext
	lxi	d,FCB1
	call	parsfn
	inx	d
	ldax	d
	dcx	d
	cpi	20h
	jnz	@dir
	ldax	d
	lxi	d,allfils
	stax	d

@dir:	call	DSK_SEL
	rc
	push	d
		call	prnt
		db	10,13,0
	pop	d
	call	PR_DIR
	call	CmdPtrToNext
	jnz	dr_pr
	ret


allfils:db	0,'???????????'

;*	*	*	*	*	*
read_f::
	call	SkipToNext
	rc
	lxi	d,fcb1
	push	d
	call	parsfn
	pop	d

	call	DSK_SEL
	rc
	XRA	A
	CALL	SRCH_F
	jc	FNF
	call	@read_f
	rc
@LP:	lxi	d,fcb1
	call	SRCH_N
	jc	rd_f@@
	call	@read_f
	jnc	@LP
	ret

rd_f@@:	call	CmdPtrToNext
	jnc	read_f
	ret

@read_f::
	push	h
	call	Copy_Fcb
	pop	h
	call	OPN_FIL
	lxi	d,cpmfcb
	call	PRNT_FN
        call	selCPM
	SYSCALL	@delete	; Delete file
	LXI	D,cpmfcb
	SYSCALL	@create	; Create file
	inr	a
	jz	DIROWF

RDF0:	call	selMSDOS
	lxi	d,RamStart
	call	Rd_From_MS
	push	psw
	call	Wt_End_Cmd
	call	selCPM
	call	Wr_To_CPM
	jc	Wrt_Err
	pop	psw
	jnc	RDF0
	LXI	D,cpmfcb
	SYSCALL	@close
        xra	a
	call	selMSDOS
	ret
Wrt_Err:
	pop	psw
	call	prnt
	db	13,10,'? CP/M write error (Disk full)',0
	stc
	ret


; *	*       *	*	*	*
write_f::
	call	SkipToNext
	lxi	d,fcb1
	call	parsfn

	lxi	d,80h
	syscall	@setdma

	lxi	d,fcb1
	ldax	d
	sta	MS_Drive

	lda	Default_CPM_Drive
	stax	d

	lxi	h,Entrs_List
	shld	Entry_Ptr

        call	selCPM
	syscall	@search_first
	inr	a
	jz	FNF
	call	Save_entry
@wr_loop:
	lxi	d,fcb1
	syscall	@search_next
	inr	a
	jz	wrt_f00
	call	Save_Entry
	jmp	@wr_loop

wrt_f00:
	lxi	h,Entrs_List
wrt_one_file:
	mov	a,m
	ora	a
	jz	wrt_f01
	call	Copy_FCB
	push	h
		call	@write_f
	pop	h
	rc
	jmp	wrt_one_file

wrt_f01:
	call	CmdPtrToNext
	jnc	write_f
	ret


Save_Entry:
	lxi	h,80h
	lxi	b,20h
@loop:	dcr	a
	jz	@ext
	dad	b
	jmp	@loop
@ext:	inx	h
	xchg
	lhld	Entry_Ptr
	mvi	c,11
	ldax	d
	mov	m,a
	inx	h
	inx	d
	dcr	c
	jnz	$-5
	mvi	m,0
	shld	Entry_Ptr
	ret

@write_f::
;	lda	MS_Drive
;	call	SelDrive
;	rc
	lxi	d,cpmfcb
	call	PRNT_FN
	call	selCPM
	syscall	@open	; Open file
	inr	a
	jz	FNF

	lxi	d,cpmfcb
	call	CRT_FIL
	jc	DIROWF

wrf0:	lxi	d,RamStart
	call	selCPM
	call	Rd_From_Cpm
	push	psw
	call	selMSDOS
	call	Wr_To_MS
	jc	MS_DOS_Wrt_Err
	call	WT_END_CMD
	pop	psw
        jnc	wrf0
	call	CLS_FIL
	call	WT_END_CMD
	call	prnt
	db	9,'Ok',0
	ora	a
	ret

MS_DOS_Wrt_Err:
	pop	psw
	call	prnt
	db	13,10,'? MS-DOS write error (Disk full)',0
	stc
	ret

; *	*       *	*	*	*
ers_f:
	call	SkipToNext
	rc
	call	@ers_f
	call	CmdPtrToNext
	jnc	ers_f
	ret


@ers_f:
	lxi	d,fcb1
	call	parsfn
	call	DSK_SEL
	rc

	xra	a
	call	SRCH_F
	rc
	push	h
	pop	d
	dcx	d
	push	h
	call	PRNT_FN
	pop	h
	call	ERS_FIL
@ers_lp:
	lxi	d,fcb1
	call	SRCH_N
	rc
	push	h
	pop	d
	dcx	d
	push	h
	call	PRNT_FN
	pop	h
	call	ERS_FIL
	jmp	@ers_lp


; *	*       *	*	*	*
kill_f:	call	SkipToNext
	rc
	lxi	d,cpmfcb
	push	d
		call	parsfn
	pop	d
	call	selCPM

@del_again:
	push	d
        	syscall	13h
	pop	d
        inr	a
	jnz	@del_again
	call	CmdPtrToNext
	jnc	kill_f
	ret

;----------------------------------------------------------------------------
chg_drive:
	mov	a,m
	call	UpCase
	cpi	'A'
	rc
	cpi	MaxDrive+1
	rnc
	sui	'A'-1
	sta	Default_CPM_Drive
	ret

;---------------------------------------------------------------------------


;	**** Basic reading procedures ****

; Read as more as possible from CPM file
Rd_From_CPM:
	lxi	h,cpmfcb
	shld	CurFCB
	lxi	h,Rd_CPM_Rec
	shld	Rd_XX_Rec+1
	lxi	h,128
	jmp	RdIntoRam

;  HL - length of information have been read
;  cy=1 - it's a last portion of information
Rd_From_MS:
	lxi	h,Rd_MS_Rec
	shld	Rd_XX_Rec+1
	lhld	ClstSize

; Reading into memory using procedure Rd_XX_Rec
RdIntoRam:
	shld	RecSize
	lxi	h,RamStart
	shld	CurPos
	xchg
	lxi	h,0
	shld	RdSize
@RdIR:	call	Rd_XX_Rec
	push	psw
	xchg
	lhld	RdSize
	dad	d
	shld	RdSize
	pop	psw
	jc	@last_r

	lhld	RecSize
	xchg
	lhld	CurPos
	dad	d
	shld	CurPos

	xchg
	lhld	RamEnd
	call	?cdehl
	jnz	@RdIR
	ora	a
@last_r:lhld	RdSize
	ret

Rd_XX_Rec:
	jmp	0


;*** Read next MS-DOS record ***
Rd_MS_Rec:
	jmp	Rd_Rec


;*** Read next CPM record ***
;   DE - RAM address to read
;   (CurFCB) - FCB for current file
; Returns:
;     HL - number of bytes actually read.
Rd_CPM_Rec:
	push	b
	push	d
	syscall	1ah
	lhld	CurFCB
	xchg
	syscall	@seqread
	lxi	h,128
	ora	a
	jz	NotEof
	stc
	lxi	h,0
NotEof:	pop	d
	pop	b
	ret

;		**** END ****

;	**** Basic writing procedures ****

; Write HL bytes to MS-DOS file
; cy = 1 if any writing errors occurs
Wr_To_MS:
	push	h
	lhld	ClstSize
	shld	RecSize
	lxi	h,Wr_MS_Rec
	jmp	WrFromRam

Wr_To_CPM:
	push	h
	lxi	h,CpmFcb
	shld	CurFCB
	lxi	h,128
	shld	RecSize
	lxi	h,Wr_CPM_Rec
WrFromRam:
	shld	Wr_XX_Rec+1
	pop	h
	shld	Bytes_To_Write
	lxi	h,RamStart
	shld	Write_Ptr
WrLoop:	lhld	Bytes_To_Write
	xchg
	lhld	RecSize
	call	?cdehl
	jc	Write_Last_Rec
	xchg
	lhld	Write_Ptr
	xchg
        push	h
	push	d
	call	Wr_XX_Rec
	pop	d
	pop	h
	rc
	dad	d
	shld	Write_Ptr
	lhld	RecSize
	call	?neghl
	xchg
	lhld	Bytes_To_Write
	dad	d
	shld	Bytes_To_Write
	jmp	WrLoop

Write_Last_Rec:
	mov	a,d
	ora	e
	rz
	lhld	Write_ptr
	xchg
Wr_XX_Rec:
	jmp	0

Wr_MS_Rec:
	jmp	Wr_Rec

Wr_CPM_Rec:
	syscall	1ah
	lhld	CurFcb
	xchg
	syscall	@seqwrt
	ora	a
	rz
	stc
	ret

	dseg
;  Different variables shared same memory
; because they are never used at the same time
Write_Ptr:
CurPos:	ds	2
Bytes_To_Write:
RdSize:	ds	2
RamEnd:	ds	2
CurFCB:	ds	2
RecSize:ds	2
	cseg
;	**** END ****

; Some different usefull subrotines
?cdehl:	mov	a,d
	cmp	h
	rnz
	mov	a,e
	cmp	l
	ret

UpCase:	cpi	60h
	rc
	sui	20h
	ret

getch:	mvi	e,0ffh
	syscall	6
	ora	a
	jz	getch
	ret

putch:	push	d
	push	b
	mov	e,a
	syscall	2
	pop	b
	pop	d
	ret

print_n:ldax	d
	inx	d
	call	putch
	dcr	c
	jnz	print_n
	ret

PRNT_FN:
	push	d
	push	d
	call	prnt	; Print copying file name
	db	10,13,9,0
  	pop	d

	inx	d
	mvi	c,8
	call	print_n
	mvi	a,'.'
	call	putch
	mvi	c,3
	call	print_n
	pop	d
	ret


PRNT:	POP	H
prnt1:	mov	e,m
	inx	h
	inr	e
	dcr	e
	jz	prnt2
	push	h
	syscall	2
	pop	h
	jmp	prnt1

prnt2:	PCHL

;**** Error handling procedures ****
DIROWF:
	call	prnt
	db	10,13,'? No directory space',0
	stc
	ret

EXIT:
if	0
	call	selCPM
	mvi	a,1
	call	ChgDrive
	lhld	oldsp
	sphl
	ret
else
	mvi	a,1
	call	ChgDrive
	jmp	0
endif


FNF:	CALL	PRNT
	DB	'     ? File not found',0
	stc
	ret

BAD:	CALL	PRNT
	DB	10,13,'? Bad sector or disk not formatted',0
	JMP	EXIT

selMSDOS:
	lda	MS_Drive
	ora	a
	jnz	ChgDrive
	inr	a
	call	ChgDrive
	ret

selCPM: push	b
	push	d
	push	h
	lda	Default_CPM_Drive
	mvi	b,1
	mov	c,a
	lda	RAM_DISK
	cmp	C
	jz	sCPM1	; Don't need to check for ramdisk
	mov	a,c
	cpi	1	; if 'A' or 'D' => disk 1
	jz	sCPM0
	cpi	4
	jz	sCPM0
	mvi	b,2	; else => disk2
sCPM0:	mov	a,b
	call	ChgDrive
;	jc	DriveNotReady
sCPM2:	call	RdBoot
        lda	FATBUF
	cpi	0e9h
	jz	sCPM3
	cpi	0ebh
	jnz	sCPM1
sCPM3:	call	prnt
	db	13,10,'Insert CP/M disk & press a key',0
	call	getch
	jmp	sCPM0
sCPM1:	pop	h
	pop	d
	pop	b
	ret

	dseg
oldsp:	ds	2
tst_buf:ds	512
	cseg

cpmfcb:	rept	36/2
	dw	0
	endm


Entry_Ptr:	ds	2
Entrs_List:
	ds	11*Max_CPM_Files+1

Default_CPM_Drive:
		db	2
CmdPos:		ds	2
command_string:	db	80,0
		ds	80
Last_Drive:	db	0ffh
MS_Drive:	ds	1
RAM_DISK:	ds	1
	end	strt

;$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$



;****** MF.ASM -  CP/M - MS-DOS filer**
;* V1.3            (C) TCHV, 1991-93  *
;* 11-Jul-1993                5:13 pm *
;**************************************

PROFI	equ	1

INCLUDE		SYSCALLS.MAC

;	 4-Mar-1992 - add wildcard support
;	10-Apr-1992 - debug wildcards
;       xx-xxx-1992 - debug memory allocation
;	08-Oct-1992 - add some features
;	11-Jul-1993 -

; Externally allocated memory
	extrn	FatBuf,RamStart,Stack

fcb1		equ	5ch


Max_CPM_Files	equ	64	; Maximum files got by SEARCH NEXT
MaxDrive	equ	'E'	; Maximum CPM drive

stksize		equ	80h
RamTop		equ	6
MaxRecSize	equ	1024
CmdLine		equ	81h

; ------ MS-DOS FILE OPERATIONS -----------
EXTRN	OPN_FIL,RD_REC,CRT_FIL,WR_REC,CLS_FIL,ERS_FIL
EXTRN	RD_FAT,PR_DIR,ClstSize
EXTRN	SRCH_F,SRCH_N

EXTRN	HOME,WT_END_CMD,ChgDrive,RdBoot
EXTRN	FD_RD_INIT

EXTRN	getstr,parsfn

extrn	?neghl

PUBLIC	BAD

; Export for PRDIR module
PUBLIC	PRNT

COMLEN		equ	80h
COMLIN		equ	81h

GET_COMLIN	macro
	lxi	h,COMLIN
	push	h
		lda	COMLEN
		add	l
		mov	l,a
		mvi	m,0
	pop	h
	endm


	.8080
STRT:
if PROFI
	MVI	A,'E'-'A'+1
	STA	Default_CPM_Drive
        sta	RAM_DISK
else
	MVI	A,'B'-'A'+1
	STA	Default_CPM_Drive
        sta	RAM_DISK
	LDA	2
	CPI	0DAH
	JZ	$+8
	MVI	A,'C'-'A'+1
        sta	RAM_DISK
	STA	Default_CPM_Drive
endif
	CALL	PRNT
	DB	10,13
DB 'Cpm - MS-DOS  Filer V1.3,11-Jul-1993              (C) Tchv, 1991-93',10,13,0

; RamEnd=RamStart+(RamTop-RamStart)&(-MaxRecSize)
	lhld	RamTop
	lxi	d,RamStart
	lxi	b,-MaxRecSize
	mov	a,l
	sub	e
	push	psw
	ana	c
	mov	l,a
	pop	psw
	mov	a,h
	sbb	d
	ana	b
	mov	h,a
	dad	d
	shld	RamEnd
;

	lxi	h,0
	dad	sp
	shld	oldsp
	lxi	sp,Stack+StkSize


	lda	FCB1+1
	lxi	h,CmdLine
	cpi	20h
	jnz	@do_command
; It's nothing to do (command line is empty)
	call	Print_Instructions
@do_loop:
	call	prnt
	db	10,13,0
	lda	Default_CPM_Drive
	adi	'A'-1
	call	putch
	call	prnt
	db	':*',0
	lxi	d,command_string
	call	getstr
        call	do_cmd
	jmp	@do_loop

@do_command:

	GET_COMLIN
	call	Do_Cmd
	jmp	exit


isspace:
	cpi	20h
	rz
	cpi	9
	ret

SkipSpaces:
	mov	a,m
	call	isspace
	rnz
	inx	h
	jmp	SkipSpaces

;----------------------------
Do_Cmd:
	call	SkipSpaces
	mov	a,m
	call	UpCase
	inx	h
	ora	a
	rz
	cpi	'@'
	jz	chg_drive
	push	psw
	call	SkipSpaces
	shld	CmdPos
	pop	psw
	CALL	UpCase
	CPI	'D'
	jz	dir_pr
	cpi	'R'
	jz	read_f
	cpi	'W'
	jz	write_f
	cpi	'E'
	jz	ers_f
	cpi	'K'
	jz	kill_f
	cpi	'X'
	jz	exit
	jmp	Print_Instructions


; Select last drive if needed
;  Returns: CY=1 if errors detected
SelDrive:
	sta	MS_Drive
	lxi	h,Last_Drive
	cmp	m
	jz	Nxt00

	sta	Last_Drive
	ora	a
	jz	Nxt00

	CALL	ChgDrive
	jnc	nxt00
	call	prnt
	db	10,13,'Drive not ready',0
	stc
	ret

DSK_SEL:
	ldax	d
	push	d
		call	SelDrive
	pop	d
	ret

NXT00:	CALL	HOME
	CALL	WT_END_CMD
	CALL	HOME
TRY_MS:	CALL	RdBoot
	LDA	FATBUF
	CPI	0e9h
	jz	nextd
	cpi	0ebh
	jz	nextd
	CALL	PRNT
	DB	10,13,'Insert MS-DOS disk & strike a key',0
	CALL	getch
	cpi	3
	stc
	rz
	JMP	TRY_MS
nextd:	CALL	RD_FAT
	xra	a
	ret

Print_Instructions:
	CALL	PRNT
	db	10,13,'MF2 action [[Drive:]file_pattern] '

	db	10,10,13,' Valid actions are :'
	db	10,13,9,9,'d - print the directory of MS-DOS disk'
	db	10,13,9,9,'r - read  file(s) from MS-DOS disk'
	db	10,13,9,9,'w - write file(s) to MS-DOS disk'
	db	10,13,9,9,'e - erase file(s) on MS-DOS disk'
	db	10,13,9,9,'k - kill file(s)  on CP/M disk'
	db	10,13,9,9,'x - exit to CP/M'
	db	10,13,9,9,'@D - change default CP/M drive to D',0
	ret


Copy_Fcb:
	lxi	d,cpmfcb
	lda	Default_CPM_Drive
	stax	d
	inx	d
	mvi	c,11
	mov	a,m
	stax	d
	inx	h
	inx	d
	dcr	c
	jnz	$-5
	mvi	c,36-12
	xra	a
	stax	d
	inx	d
	dcr	c
	jnz	$-3
	ret

; Basic MS Filer actions

; Usefull subroutines
SkipToNext:
	lhld	CmdPos
	call	SkipSpaces
	mov	a,m
	ora	a
	stc
	rz
	shld	CmdPos
	ora	a
	ret

CmdPtrToNext:
	lhld	CmdPos
@@skip:	inx	h
	mov	a,m
	ora	a
	stc
	rz
	call	isspace
	jnz	@@skip
	shld	CmdPos
	ora	a
	ret



;*	*	*	*	*	*
dir_pr::
	mov	a,m
	ora	a
	lxi	d,allfils
	jz	@dir

dr_pr:	call	SkipToNext
	lxi	d,FCB1
	call	parsfn
	inx	d
	ldax	d
	dcx	d
	cpi	20h
	jnz	@dir
	ldax	d
	lxi	d,allfils
	stax	d

@dir:	call	DSK_SEL
	rc
	push	d
		call	prnt
		db	10,13,0
	pop	d
	call	PR_DIR
	call	CmdPtrToNext
	jnz	dr_pr
	ret


allfils:db	0,'???????????'

;*	*	*	*	*	*
read_f::
	call	SkipToNext
	rc
	lxi	d,fcb1
	push	d
	call	parsfn
	pop	d

	call	DSK_SEL
	rc
	XRA	A
	CALL	SRCH_F
	jc	FNF
	call	@read_f
	rc
@LP:	lxi	d,fcb1
	call	SRCH_N
	jc	rd_f@@
	call	@read_f
	jnc	@LP
	ret

rd_f@@:	call	CmdPtrToNext
	jnc	read_f
	ret

@read_f::
	push	h
	call	Copy_Fcb
	pop	h
	call	OPN_FIL
	lxi	d,cpmfcb
	call	PRNT_FN
        call	selCPM
	SYSCALL	@delete	; Delete file
	LXI	D,cpmfcb
	SYSCALL	@create	; Create file
	inr	a
	jz	DIROWF

RDF0:	call	selMSDOS
	lxi	d,RamStart
	call	Rd_From_MS
	push	psw
	call	Wt_End_Cmd
	call	selCPM
	call	Wr_To_CPM
	jc	Wrt_Err
	pop	psw
	jnc	RDF0
	LXI	D,cpmfcb
	SYSCALL	@close
        xra	a
	call	selMSDOS
	ret
Wrt_Err:
	pop	psw
	call	prnt
	db	13,10,'? CP/M write error (Disk full)',0
	stc
	ret


; *	*       *	*	*	*
write_f::
	call	SkipToNext
	lxi	d,fcb1
	call	parsfn

	lxi	d,80h
	syscall	@setdma

	lxi	d,fcb1
	ldax	d
	sta	MS_Drive

	lda	Default_CPM_Drive
	stax	d

	lxi	h,Entrs_List
	shld	Entry_Ptr

        call	selCPM
	syscall	@search_first
	inr	a
	jz	FNF
	call	Save_entry
@wr_loop:
	lxi	d,fcb1
	syscall	@search_next
	inr	a
	jz	wrt_f00
	call	Save_Entry
	jmp	@wr_loop

wrt_f00:
	lxi	h,Entrs_List
wrt_one_file:
	mov	a,m
	ora	a
	jz	wrt_f01
	call	Copy_FCB
	push	h
		call	@write_f
	pop	h
	rc
	jmp	wrt_one_file

wrt_f01:
	call	CmdPtrToNext
	jnc	write_f
	ret


Save_Entry:
	lxi	h,80h
	lxi	b,20h
@loop:	dcr	a
	jz	@ext
	dad	b
	jmp	@loop
@ext:	inx	h
	xchg
	lhld	Entry_Ptr
	mvi	c,11
	ldax	d
	mov	m,a
	inx	h
	inx	d
	dcr	c
	jnz	$-5
	mvi	m,0
	shld	Entry_Ptr
	ret

@write_f::
;	lda	MS_Drive
;	call	SelDrive
;	rc
	lxi	d,cpmfcb
	call	PRNT_FN
	call	selCPM
	syscall	@open	; Open file
	inr	a
	jz	FNF

	lxi	d,cpmfcb
	call	CRT_FIL
	jc	DIROWF

wrf0:	lxi	d,RamStart
	call	selCPM
	call	Rd_From_Cpm
	push	psw
	call	selMSDOS
	call	Wr_To_MS
	jc	MS_DOS_Wrt_Err
	call	WT_END_CMD
	pop	psw
        jnc	wrf0
	call	CLS_FIL
	call	WT_END_CMD
	call	prnt
	db	9,'Ok',0
	ora	a
	ret

MS_DOS_Wrt_Err:
	pop	psw
	call	prnt
	db	13,10,'? MS-DOS write error (Disk full)',0
	stc
	ret

; *	*       *	*	*	*
ers_f:
	call	SkipToNext
	rc
	call	@ers_f
	call	CmdPtrToNext
	jnc	ers_f
	ret


@ers_f:
	lxi	d,fcb1
	call	parsfn
	call	DSK_SEL
	rc

	xra	a
	call	SRCH_F
	rc
	push	h
	pop	d
	dcx	d
	push	h
	call	PRNT_FN
	pop	h
	call	ERS_FIL
@ers_lp:
	lxi	d,fcb1
	call	SRCH_N
	rc
	push	h
	pop	d
	dcx	d
	push	h
	call	PRNT_FN
	pop	h
	call	ERS_FIL
	jmp	@ers_lp


; *	*       *	*	*	*
kill_f:	call	SkipToNext
	rc
	lxi	d,cpmfcb
	push	d
		call	parsfn
	pop	d
	call	selCPM

@del_again:
	push	d
        	syscall	13h
	pop	d
        inr	a
	jnz	@del_again
	call	CmdPtrToNext
	jnc	kill_f
	ret

;----------------------------------------------------------------------------
chg_drive:
	mov	a,m
	call	UpCase
	cpi	'A'
	rc
	cpi	MaxDrive+1
	rnc
	sui	'A'-1
	sta	Default_CPM_Drive
	ret

;---------------------------------------------------------------------------


;	**** Basic reading procedures ****

; Read as more as possible from CPM file
Rd_From_CPM:
	lxi	h,cpmfcb
	shld	CurFCB
	lxi	h,Rd_CPM_Rec
	shld	Rd_XX_Rec+1
	lxi	h,128
	jmp	RdIntoRam

;  HL - length of information have been read
;  cy=1 - it's a last portion of information
Rd_From_MS:
	lxi	h,Rd_MS_Rec
	shld	Rd_XX_Rec+1
	lhld	ClstSize

; Reading into memory using procedure Rd_XX_Rec
RdIntoRam:
	shld	RecSize
	lxi	h,RamStart
	shld	CurPos
	xchg
	lxi	h,0
	shld	RdSize
@RdIR:	call	Rd_XX_Rec
	push	psw
	xchg
	lhld	RdSize
	dad	d
	shld	RdSize
	pop	psw
	jc	@last_r

	lhld	RecSize
	xchg
	lhld	CurPos
	dad	d
	shld	CurPos

	xchg
	lhld	RamEnd
	call	?cdehl
	jnz	@RdIR
	ora	a
@last_r:lhld	RdSize
	ret

Rd_XX_Rec:
	jmp	0


;*** Read next MS-DOS record ***
Rd_MS_Rec:
	jmp	Rd_Rec


;*** Read next CPM record ***
;   DE - RAM address to read
;   (CurFCB) - FCB for current file
; Returns:
;     HL - number of bytes actually read.
Rd_CPM_Rec:
	push	b
	push	d
	syscall	1ah
	lhld	CurFCB
	xchg
	syscall	@seqread
	lxi	h,128
	ora	a
	jz	NotEof
	stc
	lxi	h,0
NotEof:	pop	d
	pop	b
	ret

;		**** END ****

;	**** Basic writing procedures ****

; Write HL bytes to MS-DOS file
; cy = 1 if any writing errors occurs
Wr_To_MS:
	push	h
	lhld	ClstSize
	shld	RecSize
	lxi	h,Wr_MS_Rec
	jmp	WrFromRam

Wr_To_CPM:
	push	h
	lxi	h,CpmFcb
	shld	CurFCB
	lxi	h,128
	shld	RecSize
	lxi	h,Wr_CPM_Rec
WrFromRam:
	shld	Wr_XX_Rec+1
	pop	h
	shld	Bytes_To_Write
	lxi	h,RamStart
	shld	Write_Ptr
WrLoop:	lhld	Bytes_To_Write
	xchg
	lhld	RecSize
	call	?cdehl
	jc	Write_Last_Rec
	xchg
	lhld	Write_Ptr
	xchg
        push	h
	push	d
	call	Wr_XX_Rec
	pop	d
	pop	h
	rc
	dad	d
	shld	Write_Ptr
	lhld	RecSize
	call	?neghl
	xchg
	lhld	Bytes_To_Write
	dad	d
	shld	Bytes_To_Write
	jmp	WrLoop

Write_Last_Rec:
	mov	a,d
	ora	e
	rz
	lhld	Write_ptr
	xchg
Wr_XX_Rec:
	jmp	0

Wr_MS_Rec:
	jmp	Wr_Rec

Wr_CPM_Rec:
	syscall	1ah
	lhld	CurFcb
	xchg
	syscall	@seqwrt
	ora	a
	rz
	stc
	ret

	dseg
;  Different variables shared same memory
; because they are never used at the same time
Write_Ptr:
CurPos:	ds	2
Bytes_To_Write:
RdSize:	ds	2
RamEnd:	ds	2
CurFCB:	ds	2
RecSize:ds	2
	cseg
;	**** END ****

; Some different usefull subrotines
?cdehl:	mov	a,d
	cmp	h
	rnz
	mov	a,e
	cmp	l
	ret

UpCase:	cpi	60h
	rc
	sui	20h
	ret

getch:	mvi	e,0ffh
	syscall	6
	ora	a
	jz	getch
	ret

putch:	push	d
	push	b
	mov	e,a
	syscall	2
	pop	b
	pop	d
	ret

print_n:ldax	d
	inx	d
	call	putch
	dcr	c
	jnz	print_n
	ret

PRNT_FN:
	push	d
	push	d
	call	prnt	; Print copying file name
	db	10,13,9,0
  	pop	d

	inx	d
	mvi	c,8
	call	print_n
	mvi	a,'.'
	call	putch
	mvi	c,3
	call	print_n
	pop	d
	ret


PRNT:	POP	H
prnt1:	mov	e,m
	inx	h
	inr	e
	dcr	e
	jz	prnt2
	push	h
	syscall	2
	pop	h
	jmp	prnt1

prnt2:	PCHL

;**** Error handling procedures ****
DIROWF:
	call	prnt
	db	10,13,'? No directory space',0
	stc
	ret

EXIT:
if	0
	call	selCPM
	mvi	a,1
	call	ChgDrive
	lhld	oldsp
	sphl
	ret
else
	mvi	a,1
	call	ChgDrive
	jmp	0
endif


FNF:	CALL	PRNT
	DB	'     ? File not found',0
	stc
	ret

BAD:	CALL	PRNT
	DB	10,13,'? Bad sector or disk not formatted',0
	JMP	EXIT

selMSDOS:
	lda	MS_Drive
	ora	a
	jnz	ChgDrive
	inr	a
	call	ChgDrive
	ret

selCPM: push	b
	push	d
	push	h
	lda	Default_CPM_Drive
	mvi	b,1
	mov	c,a
	lda	RAM_DISK
	cmp	C
	jz	sCPM1	; Don't need to check for ramdisk
	mov	a,c
	cpi	1	; if 'A' or 'D' => disk 1
	jz	sCPM0
	cpi	4
	jz	sCPM0
	mvi	b,2	; else => disk2
sCPM0:	mov	a,b
	call	ChgDrive
;	jc	DriveNotReady
sCPM2:	call	RdBoot
        lda	FATBUF
	cpi	0e9h
	jz	sCPM3
	cpi	0ebh
	jnz	sCPM1
sCPM3:	call	prnt
	db	13,10,'Insert CP/M disk & press a key',0
	call	getch
	jmp	sCPM0
sCPM1:	pop	h
	pop	d
	pop	b
	ret

	dseg
oldsp:	ds	2
tst_buf:ds	512
	cseg

cpmfcb:	rept	36/2
	dw	0
	endm


Entry_Ptr:	ds	2
Entrs_List:
	ds	11*Max_CPM_Files+1

Default_CPM_Drive:
		db	2
CmdPos:		ds	2
command_string:	db	80,0
		ds	80
Last_Drive:	db	0ffh
MS_Drive:	ds	1
RAM_DISK:	ds	1
	end	strt

;$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$



