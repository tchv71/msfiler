;****************** IBM PC  filer  **********************
;*              Memory allocation module		*
;*(c) TCHV  	       		    15-nov-1991, 1:18 am*
;********************************************************

malloc	macro	label,size
	public	label
label	equ	ptr
ptr	set	ptr+size
	endm

	dseg
ptr	set	$


	malloc	FatBuf,512*5
	malloc	DirBuf,1024
	malloc	Stack,80h	; stack segment
	malloc	RamStart,0

	end
dseg
ptr	set	$


	malloc	FatBuf,512*5
	malloc	DirBuf,1024
	malloc	Stack,80h	; sta