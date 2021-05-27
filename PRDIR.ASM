;$$$$  PRDIR.ASM - print directory module $$$$
;$                          (c) TCHV 1991-93 $
;$ Last modified 8-oct-1992 1:17 am          $
;$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$

; 	 8-Oct-1992 - Add multicolumn directory printing

; From MSFILES library
EXTRN	SRCH_F,SRCH_N,FND_FREE
EXTRN	ClstSize

EXTRN	?DVNHD
; From MYLIB library
EXTRN	CONOUT

	.8080
NUM_COLUMNS:	db	3

EXTRN	PRNT	; Print procedure


cr	equ	13
lf	equ	10
print	macro	text
	call	prnt
	db	text,0
	endm


;	static outdec(int n);

; OUTPUT DECIMAL NUMBER
; HL - number to print
; b  - symbol width

OUTDEC:	push	h
	lxi	h,buff
@outdc0:
	dcr	b
	xthl
	push	d
	PUSH	B
	LXI	D,10
	CALL	?DVNHD
	POP	B
	mov	c,e
	pop	d
	mov	a,h
	ora	l
	xthl
	inx	h
	mov	m,c
	jnz	@outdc0
	pop	d

@out_dc10:
	mov	a,b	; Align decimal umber by right end
	ora	A
	jz	@outdc2
	mvi	c,' '
	call	CONOUT
	DCR	B
	jmp	@out_dc10
@outdc2:
	mov	a,m
	dcx	h
	ora	a
	rm
	adi	'0'
	mov	c,a
	call	CONOUT
	jmp	@outdc2

BUFF:	DB	-1
	DS	8

; Calculate a number of FREE clusters on volume,
; return result in HL
?FREE:	push	d
	lxi	h,1	; Starting cluster-1
	lxi	d,-1
FR_00:	inx	d
	inx	h
	call	FND_FREE
	jnc	fr_00	; This cluster exists
	xchg		; There's no free clusters
	pop	d
	ret
; Runtimes
EXTRN	?mulhd,?dvnhd,?srnhb,?slhb


; PRINT DIRECTORY CONTENTS
PR_DIR::push	d
	print	'Free: '
	call	?free

	xchg	; We have a free space in clusters.
	lhld	ClstSize; We are to determine it in kilobytes.
	mvi	b,6
	call	?srnhb  ; HL = Kbytes_per_Cluster*16
	call	?mulhd
	mvi	b,4
 	call	?srnhb

	mvi	b,4
	call	outdec
	print	<' kbyte(s)',cr,lf,lf>
	pop	d
	push	d
	lda	NUM_COLUMNS
	sta	columns_left
	XRA	A
	sta	NumFils
	lxi	h,0
	shld	Occupy
	CALL	SRCH_F
	pop	d
	jc	pr_last
PR_D0:	push	d
	CALL	PR_ITM
	pop	d
	push	d
	CALL	SRCH_N
	pop	d
 	jnc	PR_D0
pr_last:print	<cr,lf,lf>
	lda	numfils
	mov	l,a
	mvi	h,0
	mvi	b,3
	call	outdec
	print	' files occupy '
	lhld	occupy
	mvi	b,4
	call	outdec
	print	' kbyte(s)'
	ret

FILPAT:	DB	' ???????????'

PR_ITM:
	push	h
	print	'   '
	pop	h
	MVI	B,8
	CALL	PRI0
	MVI	C,'.'
	CALL	CONOUT
	MVI	B,3
	CALL	PRI0
	PUSH	H
 	print	'  '
	POP	H
	LXI	B,1FH-11
	DAD	B
	MVI	B,4
	CALL	SHRT
	CALL	SHRT
	DCX	H
	MOV	D,M
	DCX	H
	MOV	E,M
	DCX	H
	ORA	A
	JZ	$+4
	INX	D
	lhld	occupy
	dad	d
	shld	occupy
	lda	numfils
	inr	a
	sta	numfils
	XCHG
	mvi	b,4
	CALL	OUTDEC
	print	<' k  !'>
	lda	columns_left
	dcr	a
	sta	columns_left
	jnz	@not_newline
	lda	NUM_COLUMNS
	sta	columns_left
	print	<cr,lf>

@not_newline:
	RET

	dseg
NumFils:	DS	1
Occupy:		ds	2
Columns_Left:	ds	2
	cseg

; Shift binary number one bit right
; HL - pointer to end of number
; B -  number length
SHRT:	PUSH	H
	PUSH	B
	XRA	A
SHR0:	MOV	A,M
	RAR
	MOV	M,A
	DCX	H
	DCR	B
	JNZ	SHR0
	POP	B
	POP	H
	RET

PRI0:	MOV	C,M
	INX	H
	CALL	CONOUT
	DCR	B
	JNZ	PRI0
	RET

	END

;$$$$$$$$$$$$$$$$ PRDIR.ASM $$$$$$$$$$$$$$$$$$




PRI0:	MOV	C,M
	INX	H
	CALL	CONOUT
	DCR	B
	JNZ	PRI0
	