/****************************************************************/
/*  Micro Monitor (umon)					*/
/*								*/
/*  Copyright Integrated Device Technology			*/
/*  August 27, 1991						*/
/*								*/
/* Programmer: Michael J. Miller				*/
/* Date Created: Nov 20, 1990					*/
/*								*/
/*	This monitor is meant to be a very simple monitor that  */
/* only needs EPROMS and a UART to work to be useful.  It does  */
/* not use memory to function.  All calculations are done in    */
/* registers.  Becareful when making changes to follow the use- */
/* -age of registers.						*/
/****************************************************************/
/* Register usage:						*/
/*	s0 - contains the current input character		*/
/*	s1 - Next to top of stack.				*/
/*	s2 - Top of stack; filled with a number after '='	*/
/*	s3 - Used by fetch and display.				*/
/*	s4 - Used by fetch, store and print.			*/
/*	s6 - Option flags.   					*/
/*		:0: Quiet flag for memory test.			*/
/*	s7 - 3rd to top of stack.				*/
/*								*/
/*								*/
/****************************************************************/
/*			Modifications				*/
/*--------------------------------------------------------------*/
/* mjm 12/6/90 Add dump, fill and compare command (ver 1.2)	*/  
/* mjm 01/18/91 Add FRAME header macro to make better listings. */
/* mjm 01/18/91 Add transfer command                            */
/* mjm Thu Mar 7,1991 Modify to work with IDT/c                 */
/* mjm 08/19/91 Added the 8530 SCC UART driver                  */
/* mjm 11/13/91 Added a data parameter to write scope loop.     */
/* njs 03/16/94 Added the uPD72001 UART driver, and		*/
/*		support for R4x000, using SDE-MIPS assembler	*/
/*								*/
/* upen 5/15/99 Bug Fix:  "store" did not autoincrement.        */
/* Marc Karasek	(iViviy Inc.) 02/25/02				*/
/*		Added support for MALTA & iDisx platforms 	*/
/* Marc Karasek	(iVivity Inc.) 5/22/02				*/
/* 		Added new commands to do incremental fill and compares */ 
/* Marc Karasek (CryptoCore Tech) 3/18/2020         */
/*      Ported this code to RISCV architecture      */	
/****************************************************************/

/********* RISCV Registers***************************
Register  | ABI         | Use by convention                     | Preserved?
:-------- | :---------- | :---------------                      | ------
x0        | zero        | hardwired to 0, ignores writes        | _n/a_
x1        | ra          | return address for jumps              | no  
x2        | sp          | stack pointer                         | yes
x3        | gp          | global pointer                        | _n/a_
x4        | tp          | thread pointer                        | _n/a_
x5        | t0          | temporary register 0                  | no
x6        | t1          | temporary register 1                  | no
x7        | t2          | temporary register 2                  | no
x8        | s0 _or_ fp  | saved register 0 _or_ frame pointer   | yes
x9        | s1          | saved register 1                      | yes
x10       | a0          | return value _or_ function argument 0 | no
x11       | a1          | return value _or_ function argument 1 | no
x12       | a2          | function argument 2                   | no
x13       | a3          | function argument 3                   | no
x14       | a4          | function argument 4                   | no
x15       | a5          | function argument 5                   | no
x16       | a6          | function argument 6                   | no
x17       | a7          | function argument 7                   | no
x18       | s2          | saved register 2                      | yes
x19       | s3          | saved register 3                      | yes
x20       | s4          | saved register 4                      | yes
x21       | s5          | saved register 5                      | yes
x22       | s6          | saved register 6                      | yes
x23       | s7          | saved register 7                      | yes
x24       | s8          | saved register 8                      | yes
x25       | s9          | saved register 9                      | yes
x26       | s10         | saved register 10                     | yes
x27       | s11         | saved register 11                     | yes
x28       | t3          | temporary register 3                  | no
x29       | t4          | temporary register 4                  | no
x30       | t5          | temporary register 5                  | no
x31       | t6          | temporary register 6                  | no
pc        | _(none)_    | program counter                       | _n/a_
********* RISCV Registers***************************/

#include "riscv.h"

#define if_cmd(r,c,lbl)  \
	ori 	t6,zero,c ;\
	bne	t6,r,1f; \
	call lbl; \
	1: nop

#define prchr(c)      \
	li	a0,c ;\
	jal umon_conout	

#define pop_reg(r)     \
	move	r,s2  ;\
	move	s2,s1 ;\
	move	s1,s7

#define pop            \
	move	s2,s1 ;\
	move	s1,s7

#define push_reg(rg)   \
	move	s7,s1 ;\
	move	s1,s2 ;\
	move	s2,rg

#define prcrlf       \
	prchr(0x0a) ;\
	prchr(0x0d)

#define prstr(str)  \
	jal     print;\
	nop		  ;\
	j	1f	  ;\
	nop		  ;\
	.string	str 	  ;\
1:	nop

#define return  \
	move	ra,s8 ;\
	jr	ra

#define save  \
	mv s8, ra

#define NOPS	nop; nop; nop

#define SWAPEND32( src, tmp0, tmp1 )\
		and	tmp0, src, 0xff;\
		srl	src,  8;\
		sll	tmp0, 8;\
		and	tmp1, src, 0xff;\
		or	tmp0, tmp1;\
		srl	src,  8;\
		sll	tmp0, 8;\
		and	tmp1, src, 0xff;\
		or	tmp0, tmp1;\
		srl	src,  8;\
		sll	tmp0, 8;\
		or	src,  tmp0


#define TEST_PATTERN1	0xA5A5A5A5
#define TEST_PATTERN2	0xDEADBEEF


  .section .text.init
  .globl _start
_start:
	
  	la t0, trap_entry
  	csrw mtvec, t0

	nop

	jal   init_uart

	li	s6,0			/* Clear option flags */

	/* Clear the stack prior to running.. */
	li s2, 0
	li s1, 0
	li s7, 0

	la t3, hellostring
1:	lb	a0,0(t3)
	beq	a0,zero,2f
	jal umon_conout
	addi t3, t3,1
	j	1b
2:


	la t3, datestring
1:	lb	a0,0(t3)
	beq	a0,zero,2f
	jal umon_conout
	addi t3, t3,1
	j	1b
2:

	la a1, date
	jal prints
	nop
	prcrlf

	la a1, hartidstring
	jal prints
	prcrlf
	csrr a0, mhartid
	jal printreg
	prcrlf

#define BOOT_HART 0x1dd2

  csrr a0, mhartid
  li   a1, BOOT_HART
  beq  a0, a1, hart0_entry
42:
	wfi					
  	j 42b
hart0_entry:


/*	prstr("\n\rBuild Time: ") */
/*
	la t2, timesring
1:	lb	a0,0(t2)
	beq	a0,zero,2f
	jal umon_conout
	addi t2, t2,1
	j	1b
2:

	la a1, time	
	addi a1, a1, 7
	jal prints
	nop
	prcrlf	
*/
GLOBAL(main_loop)

	prcrlf
	prchr(0x7c)		/* print "|" */

	jal umon_conin	/* get a command */
	mv	s0,a0		

	if_cmd(s0,0x63,compare)	/* If "c" typed then goto compare */
	if_cmd(s0,0x65,examine)	/* If "e" typed then goto examine */
	if_cmd(s0,0x69,increment) /* if "i" typed then goto increment fill */
	if_cmd(s0,0x6e,icompare) /* if "n" typed then goto increment compare */
	if_cmd(s0,0x66,fill)	/* If "f" typed then goto fill */
	if_cmd(s0,0x6a,jump)	/* If "j" typed then goto jump */
	if_cmd(s0,0x6c,load)	/* If "l" typed then goto load */
	if_cmd(s0,0x6d,memrchk)	/* If "m" typed then goto memrchk */
	if_cmd(s0,0x72,read)	/* If "r" typed then goto read */
	if_cmd(s0,0x73,store)	/* If "s" typed then goto store */
	if_cmd(s0,0x74,trans)	/* If "t" typed then goto transfer */
	if_cmd(s0,0x77,write)	/* If "w" typed then goto write */
	if_cmd(s0,0x78,memrx)	/* If "x" typed then goto memrx */
	if_cmd(s0,0x2e,printstk)/* If "." typed then goto printstk */
	if_cmd(s0,0x64,dump)	/* If "d" typed then goto dump */


	li s10, 0x2f
	sub	t1,s0,s10	/* Check to see if between '0' & '9' */
	blez t1,badcmd
	li s10, 0x39
	sub	t1,s0,s10
	bgtz t1,badcmd	/* if a number then go get it. */

	prchr(0x3d)		/* Print "=" */
	prchr(0x20)		/* Print space */
	prchr(0x20)		/* Print space */
	jal get_number
	push_reg(a0)		/* push the stack */
	j	main_loop
	
badcmd:
	prchr(0x3f)		/* Else print "?" */

	j	main_loop


/****************************************************************/
/*  This code segment gets a number from the key board and puts */
/* it to register a0. The number must be composed of   */
/* digits.  Other than hex will be ignored.                     */
/****************************************************************/

GLOBAL(get_number)
	save
	mv	t3,zero
get_next:
	li t4, 0x30
	sub	t1,s0,t4		/* subtract base '0' */
	bltz t1,oops		/* ascii char less than '0' */
	li t4, 0x09
	sub	t2,t1,t4		/* is it between '0' and '9' ? */
	blez	t2,2f		/* if so branch to got one */	
	li t4, 0x07
	sub	t1,t1,t4		/* subtract next base out (0x37 total) */
	li t4, 0x0a
	sub	t2,t1,t4	 	/* is it less than 'A' ? */
	bltz t2,oops		/* ignore if so */
	li t4, 0x10
	sub	t2,t1,t4		/* is it between 'A' and 'F' ? */
	bltz t2,2f			/* if so branch to got one */
	li t4, 0x20
	sub	t1,t1,t4		/* subtract out next base (0x57 total)*/
	li t4, 0x0a
	sub	t2,t1,t4		/* is it less than 'A' ? */
	bltz t2,oops		/* ignore if so */
	li t4, 0x10
	sub	t2,t1,t4		/* is it between 'a' and 'f' */
	bgez t2,oops		/* if not try again */
	

2:
	slli t3,t3,4		/* Add it into the accumulator */
	or	t3,t3,t1

	mv	a0,s0
	jal umon_conout


oops:
	jal umon_conin		/* get hex number */
	li t2, 0x0d
	sub t1,a0,t2	/* is it a return char ? */
	beqz t1, got_num
	mv 	s0,a0

	j	get_next

got_num:
	mv	a0,t3
	return

/****************************************************************/
/*  This code segment jump to the location pointed to by S2.    */
/****************************************************************/
GLOBAL(jump)
	mv	a0,s0		/* echo the command character */
	jal umon_conout
	prchr(0x20)
	li t1, 0xfffffffffffffffc
	and s2, s2, t1 	/* make sure its a word address */
	mv	a0,s2		/* print the jump address      */
	jal printreg
	pop_reg(t0)
	jr	t0		/* Jump there!                 */

/****************************************************************/
/*  This code segment prints whats in the stack and leaves the  */
/* stack alone.    (s2, s1 & s7).                               */
/****************************************************************/
GLOBAL(printstk)
	mv	a0,s2
	jal printreg

	prchr(0x2d)
	prchr(0x3e)

	mv 	a0,s1
	jal printreg

	prchr(0x2d)
	prchr(0x3e)
	
	mv	a0,s7
	jal printreg

	j	main_loop


/****************************************************************/
/*  Store data command.  This command stores the data on the 	*/
/* top of the stack into memory by the location point to by	*/
/* address contained in the next to the top of stack.  The	*/
/* stack is poped so that only the address remains on the stack.*/
/* The address on the stack is increamented by the size of the  */
/* item stored.							*/
/****************************************************************/
/* Usage:							*/
/*  sb - stores a byte						*/
/*  sh - stores a half word					*/
/*  sw - stores a word						*/
/****************************************************************/
GLOBAL(store)
        mv    a0,s0           /* Echo the command */
        jal umon_conout
        jal umon_conin
        mv    s0,a0
        mv    s4,s2
        mv    s3,s1
        if_cmd(s0,0x62,stb)
        if_cmd(s0,0x77,stw)
        if_cmd(s0,0x64,std)
        if_cmd(s0,0x68,sth)
        prchr(0x3f)
        j       main_loop

stb:
        mv    a0,s0
        jal umon_conout
        prchr(0x20)		
        sb      s2,0(s1)        /* This is the store byte */
        mv    	s4,s1
		mv		s3,s2
        andi    s3,s3,0x0ff
        addi    s1,s1,1
		pop			/* Added by upen to cause autoincrement */
        j       pr_s43

stw:
        mv    	a0,s0
    	jal 	umon_conout
        prchr(0x20)
		li t1, 0xfffffffffffffffc
        and     s1,s1,t1   /* Make sure its a word address */
        sw      s2,0(s1)        /* This is the store word */
        mv    	s4,s1
		mv		s3,s2
        addi    s1,s1,4
		pop			/* Added by upen to cause autoincrement */
        j       pr_s43

sth:
        mv    	a0,s0
        jal umon_conout
        prchr(0x20)
		li t1, 0xfffffffffffffffe
        and     s1,s1,t1   	/* Make sure its a half word address */
        sh      s2,0(s1)    /* This is the store half word */
        mv    	s4,s1
		mv		s3,s2
		li t1, 0x0ffff
        and     s3,s3, t1
        addi    s1,s1,2
		pop			/* Added by upen to cause autoincrement */
        j       pr_s43

std:	
		mv	a0,s0
		jal umon_conout
		prchr(0x20)
		li t1, 0xfffffffffffffff8
		and	s1,s1,t1	/* Make sure its a dword address */
		sd	s2,0(s1)	/* This is the store double word */
		mv	s4,s1
		mv	s3,s2
		addi s1,s1,8
		pop			/* Added by upen to cause autoincrement */
		j 	pr_s43

/****************************************************************/
/*  Load data command.  This command fetches and prints the data*/
/* from the memory location pointed to by address contained     */
/* in the next to the top of stack.  The address on the stack is*/
/* increamented by the size of the item fetched.		*/
/****************************************************************/
/* Usage:							*/
/*  lb - fetches a byte						*/
/*  lh - fetches a half word					*/
/*  lw - fetches a word						*/
/***************************************************************/
GLOBAL(load)
	mv	a0,s0		/* Echo the command */
	jal umon_conout		
	jal umon_conin
	mv	s0,a0
	if_cmd(s0,0x62,ftb)
	if_cmd(s0,0x77,ftw)
	if_cmd(s0,0x68,fth)
	if_cmd(s0,0x64,ftd)
	prchr(0x3f)
	j	main_loop

ftd:	
	mv	a0,s0
	jal umon_conout
	prchr(0x20)		/* Print space */
	li t1, 0xfffffffffffffff8
	and	s2,s2,t1	/* Make sure its a dword address */
	ld	s3,0(s2)	/* This is the load dword */
	mv	s4,s2
	addi s2,s2,8
	j	pr_s43		/* Print result */

ftw:	
	mv	a0,s0
	jal umon_conout
	prchr(0x20)		/* Print space */
	li t1, 0xfffffffffffffffc
	and	s2,s2,t1	/* Make sure its a word address */
	lwu	s3,0(s2)	/* This is the load word */
	mv	s4,s2
	addi s2,s2,4
	j	pr_s43		/* Print result */

fth:	
	mv	a0,s0
	jal umon_conout
	prchr(0x20)		/* Print space */
	li t1, 0xfffffffffffffffe
	and	s2,s2,t1	/* Make sure its a word address */
	lhu	s3,0(s2)	/* This is the load  half word */
	mv	s4,s2
	addi s2,s2,2
	j	pr_s43		/* Print result */

ftb:	
	mv	a0,s0
	jal	umon_conout
	prchr(0x20)		/* Print space */
	lbu	s3,0(s2)	/* This is the load  byte */
	mv	s4,s2
	addi s2,s2,1
	j	pr_s43		/* Print result */
	

pr_s43:
	mv 	a0,s4
	jal printreg

	prchr(0x2d)
	prchr(0x3e)

pr_s3:
	mv 	a0,s3
	jal printreg
	j	main_loop


/****************************************************************/
/*  Examine data command.  This command fetches and prints the data*/
/* from the memory location pointed to by address contained     */
/* in the next to the top of stack.  It will then let you modify */
/* the data at the address or step to the next data in memory. */
/* The address on the stack is increamented by the size of the item fetched. */
/****************************************************************/
/* Usage:							*/
/*  eb - fetches a byte						*/
/*  eh - fetches a half word					*/
/*  ew - fetches a word						*/
/***************************************************************/
GLOBAL(examine)
	mv	a0,s0		/* Echo the command */
	jal umon_conout		
	jal umon_conin
	mv	s0,a0
	if_cmd(s0,0x62,etb)
	if_cmd(s0,0x77,etw)
	if_cmd(s0,0x68,eth)
	if_cmd(s0,0x64,etd) # Sugan added for mips3 support
	prchr(0x3f)
	j	main_loop

etd:	
	mv	a0,s0
	jal umon_conout
	prchr(0x20)		/* Print space */
	li t1, 0xfffffffffffffff8
	and	s2, s2, t1	/* Make sure its a dword address */
1:
	ld	s3,0(s2)	/* This is the load dword */
	mv	s4,s2
	/* Print result */
	mv 	a0,s4
	jal printreg
	prchr(0x20)
	prchr('=')
	prchr(0x20)
	mv 	a0,s3
	jal printreg
	/* Print . and wait for input from user */
	prchr(0x20)		/* Print space */
	prchr(0x20)		/* Print space */
	prchr('.')		/* Print . */

	jal umon_conin
	mv	s0,a0
	
	li t2, 0x2f
	sub	t1, s0, t2	/* Check to see if between '0' & '9' */
	blez	t1, 3f
	li t2, 0x39
	sub	t1, s0, t2
	bgtz	t1, 3f	/* if a number then go get it. */
	prchr(0x20)		/* Print space */
	jal get_number
	push_reg(a0)		/* push the stack */
	/* We now have the new value for this location on the stack */
	/* Now s1 haS location and s2 has new value */
	sd s2, 0(s1)
	mv s2, s1
	addi s2, s2, 8
	prcrlf
	j 1b

etw:	
	mv	a0,s0
	jal umon_conout
	prchr(0x20)		/* Print space */
	li t1, 0xfffffffffffffffc
	and	s2, s2, t1 	/* Make sure its a word address */
1:
	lwu	s3,0(s2)	/* This is the load word */
	mv	s4,s2
	/* Print result */
	mv 	a0,s4
	jal printreg
	prchr(0x20)
	prchr('=')
	prchr(0x20)
	mv 	a0,s3
	jal printreg
	/* Print . and wait for input from user */
	prchr(0x20)		/* Print space */
	prchr(0x20)		/* Print space */
	prchr('.')		/* Print . */

	jal umon_conin
	mv	s0,a0

	li t2, 0x2f
	sub	t1,s0,t2	/* Check to see if between '0' & '9' */
	blez	t1, 3f
	li t2, 0x39
	sub	t1, s0, t2
	bgtz	t1, 3f	/* if a number then go get it. */
	prchr(0x20)		/* Print space */
	jal get_number
	push_reg(a0)		/* push the stack */
	/* We now have the new value for this location on the stack */
	/* Now s1 haS location and s2 has new value */
	sw s2, 0(s1)
	mv s2, s1
	addi s2, s2, 4
	prcrlf
	j 1b

eth:	
	mv	a0,s0
	jal umon_conout
	prchr(0x20)		/* Print space */
	li t1, 0xfffffffffffffffe
	and	s2, s2, t1	/* Make sure its a half-word address */
1:
	lhu	s3,0(s2)	/* This is the load  half word */
	mv	s4,s2
	/* Print result */
	mv 	a0, s4
	jal printreg
	prchr(0x20)
	prchr('=')
	prchr(0x20)
	mv a0, s3
	jal printreg
	/* Print . and wait for input from user */
	prchr(0x20)		/* Print space */
	prchr(0x20)		/* Print space */
	prchr('.')		/* Print . */

	jal umon_conin
	mv	s0,a0
	
	li t2, 0x2f
	sub	t1,s0, t2	/* Check to see if between '0' & '9' */
	blez	t1, 3f
	li t2, 0x39
	sub	t1, s0, t2
	bgtz	t1, 3f	/* if a number then go get it. */
	prchr(0x20)		/* Print space */
	jal get_number
	push_reg(a0)		/* push the stack */
	/* We now have the new value for this location on the stack */
	/* Now s1 haS location and s2 has new value */
	sh s2, 0(s1)
	mv s2, s1
	addi s2, s2, 2
	prcrlf
	j 1b


etb:	
	mv	a0,s0
	jal umon_conout
	prchr(0x20)		/* Print space */
1:
	lbu	s3,0(s2)	/* This is the real actual load  byte */
	mv	s4,s2
	/* Print result */
	mv 	a0,s4
	jal printreg
	prchr(0x20)
	prchr('=')
	prchr(0x20)
	mv 	a0, s3
	jal printreg
	/* Print . and wait for input from user */
	prchr(0x20)		/* Print space */
	prchr(0x20)		/* Print space */
	prchr('.')		/* Print . */

	jal umon_conin
	mv	s0,a0
	
	li t2, 0x2f
	sub	t1,s0,t2	/* Check to see if between '0' & '9' */
	blez	t1, 3f
	li t2, 0x39
	sub	t1, s0, t2
	bgtz	t1, 3f	/* if a number then go get it. */
	prchr(0x20)		/* Print space */
	jal get_number
	push_reg(a0)		/* push the stack */
	/* We now have the new value for this location on the stack */
	/* Now s1 haS location and s2 has new value */
	sb s2, 0(s1)
	mv s2, s1
	addi s2, s2, 1
	prcrlf
	j 1b
	
3:
	prchr(0x3f)		/* Else print "?" */
	j	main_loop


/****************************************************************/
/*  This code segment prints a number from the key board in     */
/* register a0.                                                 */
/****************************************************************/
GLOBAL(printreg)
	save
	mv 	t3,a0
	li	t6,16

1:
	srli a0,t3,60	/* Get the top nibble */

	addi a0,a0,0x30		/* Convert it to ascii */
	li t5, 0x39
	sub	t4,a0,t5
	blez	t4,2f		/* Print it if between 0 & 9 */
	addi a0,a0,0x27		/* Else add a little more for a to f */
2:
	jal umon_conout		/* Output the character */

	slli t3,t3,4		/* Get the next digit */

	li t1, 1
	sub	t6, t6, t1		/* Bump the nibble count */
	bgtz	t6,1b	
	return

/****************************************************************/
/*  This code segment prints a character string pointed to by   */
/* register ra.  Uses register t2 ; assumes that conout dosen't */
/* use t2.				                        */
/****************************************************************/
GLOBAL(print)
	save
	addi	t2,ra,8
1:
	lb	a0,0(t2)
	beq	a0,zero,2f
	jal umon_conout
	addi t2, t2,1
	j	1b
2:
	return

/****************************************************************/
/*  This code segment prints a character string pointed to by   */
/* register a1.  Used to print build date & time	            */
/****************************************************************/
GLOBAL(prints)
	save
1:
	lbu	a0,0(a1)
	beq	a0,zero,2f
	jal umon_conout
	li t1,1
	add	a1,a1,t1
	j	1b
2:
	return

	

/****************************************************************/
/*  dump data command.  This command fetches and prints the data*/
/* from the memory locations pointed to by address range con-	*/
/* -tained on the top of stack. 				*/
/****************************************************************/
/* Usage:							*/
/*	|xxxxx   - Dump start address				*/
/*	|yyyyy	- Dump last address				*/
/*	|d							*/
/****************************************************************/
GLOBAL(dump)
	mv	a0,s0		/* Echo the command */
	jal umon_conout		
	pop_reg(s4)		/* Pop terminate address	*/
	li t1, 0xfffffffffffffffc
	and	s4, s4, t1	/* Make sure its a word address */

	/* The current read address is s2*/
	and	s2, s2, t1	/* Make sure its a word address */
	prcrlf
1:
	jal kb_wait		/* Test keyboard and wait 	*/
	
	mv	a0,s2		/* Print the load address	*/
	jal printreg

	prchr(0x2d)
	prchr(0x3e)

	lw	a0,0(s2)		/* Load the word		*/
	li t1, 0xffffffff 	/*  grab the lower word only */ 
	and a0, a0, t1
	jal printreg		/* Print it			*/
	prcrlf

	addi s2,s2,4		/* Bump the load address	*/
	sub	t0,s4,s2	/* Compare load address vs term */
	bgtz	t0,1b		/* Branch if not done		*/

	pop

	j	main_loop

kb_wait:
	save
	jal constat		/* Test for console status	*/
	bne	a0,zero,1f	/* Skip wait if no input	*/
	return			/* Return if no input		*/
1:
	jal umon_conin		/* Get console input		*/
	if_cmd(a0,0x73,wait)	/* If "s";  go wait		*/
	if_cmd(a0,0x13,wait)	/* If control-s;  go wait	*/
	return			/* Else false alarm; return	*/

wait:
/*	prstr(" Type '^q' or 'q' to continue, '.' to terminate.\n\r") */
	la t3, promptstring
1:	lb	a0,0(t3)
	beq	a0,zero,2f
	jal umon_conout
	addi t3, t3,1
	j	1b
2:

1:	jal umon_conin		/* Get console input		*/
	if_cmd(a0,0x2e,main_loop)/* If "." done waiting; goto main */
	if_cmd(a0,0x71,donew)	/* If "q" ;  done waiting	 */
	if_cmd(a0,0x11,donew)	/* If control-q ;  done waiting  */
	j	1b		/* Else wait			*/

donew:
	return			/* Done waiting ; return	*/

/****************************************************************/
/*  fill data command.  This command stores data to memory      */
/* locations pointed to by address range contained on the top 	*/
/* of stack. 							*/
/****************************************************************/
/* Usage:							*/
/*	|xxxxx   - Fill start address				*/
/*	|yyyyy	- fill last address				*/
/*	|zzzzz	- Fill pattern					*/
/*	|f							*/
/****************************************************************/

GLOBAL(fill)
	mv	a0,s0		/* Echo the command */
	jal umon_conout
	jal umon_conin /* Get next char in command */
	mv	s0,a0		
	pop_reg(s3)		/* Pop the fill data pattern	*/
	pop_reg(s4)		/* Pop terminate address	*/
	li t1, 0xfffffffffffffffc
	and	s4, s4, t1	/* Make sure its a word address */

					/* The current read address is s2*/
	li t1, 0xfffffffffffffffc
	and	s2,s2,t1	/* Make sure its a word address */
	prcrlf

1:
	sw	s3,0(s2)	/* Store the word		*/

	addi s2,s2,4		/* Bump the store address	*/
	sub	t0,s4,s2		/* Compare store address vs term */
	bgtz	t0,1b		/* Branch if not done		*/

	pop
	j	main_loop


/****************************************************************/
/*  increment fill data command.  This command stores data to memory      */
/* locations pointed to by address range contained on the top 	*/
/* of stack.  It will increment the pattern by 1 for each location stored too */
/****************************************************************/
/* Usage:							*/
/*	|xxxxx   - Fill start address			*/
/*	|yyyyy	- fill last address				*/
/*	|zzzzz	- Fill pattern					*/
/*	|ib - fill with bytes					*/
/*	|ih - fill with shorts					*/
/*	|iw - fill with words					*/
/****************************************************************/

GLOBAL(increment)
	mv	a0,s0		/* Echo the command */
	jal umon_conout
	jal umon_conin /* Get next char in command */
	mv	s0,a0		
	pop_reg(s3)		/* Pop the fill data pattern	*/
	mv t5, s3		/* Save the beginning pattern for wrap-around */
	pop_reg(s4)		/* Pop terminate address	*/

/* The current increment address is s2*/
	if_cmd(s0,0x62,ib)	/* Fill Byte */	
	if_cmd(s0,0x68,ih)	/* Fill Short */
	if_cmd(s0,0x77,iw)	/* Fill Word */
	prchr(0x3f)
	j	main_loop

ib: 
	mv	a0,s0
	jal umon_conout
ib1:	
	sb s3, 0(s2)
	addi s2,s2, 1		/* Bump the store address */
	li	t3, 0xff		/* Protect against a overflow exception */
	sub t0, t3, s3		/* Compare against max value, check for wrap-around */
	bgtz t0, ib2	
	mv s3, t5			/* We have wrap-around reset the store variable */
	j ib3
ib2:
	addi s3, s3, 1			/* Bump the store value */
ib3:
	sub t0, s4, s2		/* Compare the store address vs last address */
	bgtz t0, ib1
	j idone	

ih:
	mv	a0,s0
	jal umon_conout
	li t1, 0xfffffffffffffffe
	and	s4,s4,t1	/* Make sure its a short address */
	and	s2,s2,t1	/* Make sure its a short address */
ih1:
	sh s3, 0(s2)
	addi s2,s2,2			/* Bump the store address */
	li	t3, 0xffff		/* Protect against a overflow exception */
	sub t0, t3, s3		/* Compare against max value, check for wrap-around */
	bgtz t0, ih2
	mv s3, t5			/* We have wrap-around reset the store variable */
	j ih3
ih2:
	addi s3, s3, 1			/* Bump the store value */
ih3:
	sub t0, s4, s2		/* Compare the store address vs last address */
	bgtz t0, ih1
	j idone

iw:
	mv	a0,s0
	jal umon_conout
	li t1, 0xfffffffffffffffc
	and	s4,s4,t1	/* Make sure its a word address */
	and	s2,s2,t1	/* Make sure its a word address */
iw1:
	sw s3, 0(s2)
	addi s2, s2, 4			/* Bump the store address */
	li	t3, 0xffffffff	/* Protect against a overflow exception */
	sub t0, t3, s3		/* Compare against Max value, check for wrap-around */
	bgtz t0, iw2
	mv s3, t5			/* We have wrap-around reset the store variable */
	j iw3
iw2:
	addi s3, s3, 1			/* Bump the store value */
iw3:
	sub t0, s4, s2		/* Compare the store address vs last address */
	bgtz t0, iw1
idone:

	pop

	j	main_loop

/****************************************************************/
/*  increment compare data command.  This command compares data to memory      */
/* locations pointed to by address range contained on the top 	*/
/* of stack.  It will increment the pattern by 1 for each location compared */
/****************************************************************/
/* Usage:							*/
/*	|xxxxx   - Fill start address			*/
/*	|yyyyy	- fill last address				*/
/*	|zzzzz	- Fill pattern					*/
/*	|nb - fill with bytes					*/
/*	|nh - fill with shorts					*/
/*	|nw - fill with words					*/
/****************************************************************/
GLOBAL(icompare)
	mv	a0,s0		/* Echo the command */
	jal umon_conout
	jal umon_conin /* Get next char in command */
	mv	s0,a0		
	pop_reg(s3)		/* Pop the compare data pattern	*/
	mv t5, s3		/* Save the beginning pattern for wrap-around */
	pop_reg(s4)		/* Pop terminate address	*/

/* The current read address is s2*/
	if_cmd(s0,0x62,nb)	/* Compare Byte */	
	if_cmd(s0,0x68,nh)	/* Compare Short */
	if_cmd(s0,0x77,nw)	/* Compare Word */
	prchr(0x3f)
	j	main_loop

nb: 
	mv	a0,s0
	jal umon_conout
	prcrlf
	andi s3, s3, 0xff		/* Sanity check on the compare value */
nb1:
	lbu t2, 0(s2)
	sub t0, s3, t2
	bnez t0, cmperror
	addi s2, s2, 1		/* Bump the compare address */
	li	t3, 0xff		/* Protect against a overflow exception */
	sub t0, t3, s3		/* Compare against max value, check for wrap-around */
	bgtz t0, nb2 	
	mv s3, t5			/* We have wrap-around reset the compare variable */	
	j nb3
nb2:
	addi s3, s3, 1			/* Bump the compare value */
nb3:	
	sub t0, s4, s2		/* Compare the compare address vs last address */
	bgtz t0, nb1

	j ndone	

nh:
	mv	a0,s0
	jal umon_conout
	prcrlf
	li t1, 0xffff
	and s3, s3, t1		/* Sanity check on compare value */
	li t1, 0xfffffffffffffffe
	and	s4,	s4, t1		/* Make sure its a compare address */
	and	s2, s2, t1		/* Make sure its a compare address */
nh1:
	lhu t2, 0(s2)
	sub t0, s3, t2
	bnez t0, cmperror
	addi s2, s2, 2			/* Bump the compare address */
	li	t3, 0xffff		/* Protect against a overflow exception */
	sub t0, t3, s3		/* Compare against max value, check for wrap-around */
	bgtz t0, nh2
	mv s3, t5			/* We have wrap-around reset the compare variable */
	j nh3
nh2:
	addi s3, s3, 1		/* Bump the compare value */
nh3:
	sub t0, s4, s2		/* Compare the compare address vs last address */
	bgtz t0, nh1

	j ndone

nw:
	mv	a0,s0
	jal umon_conout
	prcrlf
	li t1, 0xfffffffffffffffc
	and	s4, s4, t1		/* Make sure its a word address */
	and	s2, s2, t1		/* Make sure its a word address */
nw1:
	lwu t2, 0(s2)
	sub t0, s3, t2
	bnez t0, cmperror
	addi s2, s2, 4		/* Bump the compare address */
	li	t3, 0xffffffff	/* Protect against a overflow exception */
	sub t0, t3, s3		/* Compare against Max value, check for wrap-around */
	bgtz t0, nw2
	mv s3, t5			/* We have wrap-around reset the compare variable */
	j nw3
nw2:
	addi s3, s3, 1		/* Bump the compare value */
nw3:
	sub t0, s4, s2		/* Compare the compare address vs last address */
	bgtz t0, nw1
	
	j ndone

cmperror:
	mv t5, t2
/*	prstr("Found ")*/
	la t3, foundstring
1:	lb	a0,0(t3)
	beq	a0,zero,2f
	jal umon_conout
	addi t3, t3,1
	j	1b
2:

	mv	a0,t5
	jal printreg 

/*	prstr(" at ") */
	la t3, atstring
1:	lb	a0,0(t3)
	beq	a0,zero,2f
	jal umon_conout
	addi t3, t3,1
	j	1b
2:

	mv	a0,s2
	jal printreg

/*	prstr(" pattern ") */
	la t3, patternstring
1:	lb	a0,0(t3)
	beq	a0,zero,2f
	jal umon_conout
	addi t3, t3,1
	j	1b
2:

	mv 	a0, s3
	jal printreg	
	prcrlf	
ndone:
	pop
	j	main_loop

/****************************************************************/
/*  transfer data command.  This command transfers data between */
/* locations pointed to by address range contained on the top 	*/
/* of stack. 							*/
/****************************************************************/
/* Usage:							*/
/*	|xxxxx  - block source start address			*/
/*	|yyyyy	- block source last address			*/
/*	|zzzzz	- block destination address			*/
/*	|t							*/
/****************************************************************/

GLOBAL(trans)
	mv	a0,s0		/* Echo the command */
	jal umon_conout		
	pop_reg(s3)		/* Pop the destination address  */
	li t1, 0xfffffffffffffffc
	and	s3,	s3, t1	/* Make sure its a word address */

	pop_reg(s4)		/* Pop src terminate address	*/
	and	s4,	s4, t1	/* Make sure its a word address */

					/* The current read address is s2*/
	and	s2, s2, t1	/* Make sure its a word address */
	prcrlf
trnloop:
	jal kb_wait

	lwu	t0,0(s2)	/* Load the word		*/
	sw	t0,0(s3)	/* Store the word		*/

	addi s3,s3,4		/* Bump the Dest address	*/
	addi s2,s2,4		/* Bump the Src address  	*/
	sub	t0,s4,s2	/* Compare cur address vs term */
	bgtz	t0,trnloop	/* Branch if not done		*/

	pop
	j	main_loop


/****************************************************************/
/*  compare data command.  This command compares data to memory */
/* locations pointed to by address range contained on the top 	*/
/* of stack. 							*/
/****************************************************************/
/* Usage:							*/
/*	|xxxxx  - Compare start address				*/
/*	|yyyyy	- Compare last address				*/
/*	|zzzzz	- Compare pattern				*/
/*	|c							*/
/****************************************************************/

GLOBAL(compare)
	mv	a0,s0		/* Echo the command */
	jal umon_conout		
	pop_reg(s3)		/* Pop the compare data pattern	*/
	pop_reg(s4)		/* Pop terminate address	*/
	li t1, 0xfffffffffffffffc
	and	s4,	s4, t1	/* Make sure its a word address */

					/* The current read address is s2*/
	and	s2,s2,t1	/* Make sure its a word address */
	prcrlf
cmploop:
	jal kb_wait

	lwu	t0,0(s2)	/* Load the word		*/
	beq	t0,s3,cmp_mat	/* If no matche then notify	*/	

	mv	s0,t0

/*	prstr("Found ") */
	la t3, foundstring
1:	lb	a0,0(t3)
	beq	a0,zero,2f
	jal umon_conout
	addi t3, t3,1
	j	1b
2:

	mv	a0,s0
	jal printreg 

/*	prstr(" at ") */
	la t3, atstring
1:	lb	a0,0(t3)
	beq	a0,zero,2f
	jal umon_conout
	addi t3, t3,1
	j	1b
2:

	mv	a0,s2
	jal printreg
	prcrlf	
cmp_mat:
	addi s2,s2,4		/* Bump the Compare address	*/
	sub	t0,s4,s2	/* Compare cur address vs term */
	bgtz	t0,cmploop	/* Branch if not done		*/

	pop
	j	main_loop


/****************************************************************/
/*  This code segment enters into an endless loop to read the   */
/* location pointed to by the TOS (S2).                         */
/****************************************************************/
/* Usage:							*/
/*  rb - fetches a byte						*/
/*  rh - fetches a half word					*/
/*  rw - fetches a word						*/
/***************************************************************/
GLOBAL(read)
	mv	a0,s0		/* Echo the command */
	jal umon_conout		
	jal umon_conin
	if_cmd(s0,0x62,rb)
	if_cmd(s0,0x77,rw)
	if_cmd(s0,0x64,rd)
	if_cmd(s0,0x68,rh)
	prchr(0x3f)
	j	main_loop

rd:
	mv	a0,s0		/* Echo the command */
	jal umon_conout		
	li t1, 0xfffffffffffffff8
	and	s2,	s2, t1	/* Make sure its a dword address */
1:
	ld	zero,0(s2)	/* Load forever */
	j	1b
	
rw:
	mv	a0,s0		/* Echo the command */
	jal	umon_conout
	li t1, 0xfffffffffffffffc		
	and	s2,	s2, t1	/* Make sure its a word address */
1:
	lwu	zero,0(s2)	/* Load forever */
	j	1b

rh:
	mv	a0,s0		/* Echo the command */
	jal umon_conout		
	li t1, 0xfffffffffffffffe
	and	s2,	s2, t1	/* Make sure its a half word address */
1:
	lhu	zero,0(s2)	/* Load forever */
	j	1b

rb:
	mv	a0,s0		/* Echo the command */
	jal umon_conout		
1:
	lbu	zero,0(s2)	/* Load forever */
	j	1b

/****************************************************************/
/*  This code segment enters into an endless loop to write the  */
/* value in TOS (S2) to the  location pointed to by the next to */
/* TOS (S1).                                                    */
/****************************************************************/
/* Usage:							*/
/*  wb - writes a byte						*/
/*  wh - writes a half word					*/
/*  ww - writes a word						*/
/***************************************************************/
GLOBAL(write)
	mv	a0,s0		/* Echo the command */
	jal umon_conout		
	jal umon_conin
	mv	s0,a0
	if_cmd(s0,0x62,wb)
	if_cmd(s0,0x77,ww)
	if_cmd(s0,0x64,wd)
	if_cmd(s0,0x68,wh)
	prchr(0x3f)
	j	main_loop

wd:
	mv	a0,s0		/* Echo the command */
	jal umon_conout		
	li t1, 0xfffffffffffffff8
	and	s1,	s1, t1	/* Make sure its a dword address */
1:
	sd	s2,0(s1)	/* store forever */
	j	1b

ww:
	mv	a0,s0		/* Echo the command */
	jal umon_conout		
	li t1, 0xfffffffffffffffc
	and	s1,	s1, t1	/* Make sure its a word address */
1:
	sw	s2,0(s1)	/* store forever */
	j	1b

wh:
	mv	a0,s0		/* Echo the command */
	jal umon_conout		
	li t1, 0xfffffffffffffffe
	and	s1,	s1, t1	/* Make sure its a half word address */
1:
	sh	s2,0(s1)	/* Store forever */
	j	1b

wb:
	mv	a0,s0		/* Echo the command */
	jal umon_conout		
1:
	sb	s2,0(s1)	/* store forever */
	j	1b

/****************************************************************/
/*  This code segment enters into an memory test loop.  The     */
/* range of the loop is specified by TOS (S2) and NOS (S1). This*/
/* test first writes a pattern through the range of address and */
/* then reads and compares to see if the pattern is correct. This*/
/* will test address lines and if refreash is happening often	*/
/* enough.  A good test is to pick a large range (1 meg) and 	*/
/* test it for bytes, half words and words. Let run over night	*/
/* each time.							*/
/****************************************************************/
/* Usage:							*/
/*  mb - writes a byte						*/
/*  mh - writes a half word					*/
/*  mw - writes a word						*/
/****************************************************************/
GLOBAL(memrchk)
	mv	a0,s0		/* Echo the command */
	jal umon_conout		
	jal umon_conin
	mv	s0,a0
	if_cmd(s0,0x62,mb)
	if_cmd(s0,0x77,mw) 
	if_cmd(s0,0x68,mh) 
	if_cmd(s0,0x71,mq) 
	prchr(0x3f)
	j	main_loop

mq:
	mv	a0,s0		/* Echo the command */
	jal umon_conout		
	ori	s6, s6,1		/* set quiet flag */
	j	main_loop

mb:
	mv	a0,s0
	jal umon_conout
	prchr(0x20)
	mv 	a0,s1		/* echo the range */
	jal printreg
	prchr(0x2d)
	prchr(0x3e)
	mv 	a0,s2
	jal printreg
	prcrlf
	li	t5,0

mbl:
	jal kb_wait
	addi t5, t5,1
	andi t5, t5, 0xff
	mv	t3,s1		/* get set up */
	mv	t4,s2
	mv	t6,t5
	prchr(0x0d)
	prchr(0x2d)
2:
	sb	t6,0(t3)	/* loop to write the test pattern */
	addi t6,t6,1
	andi t6,t6,0x0ff
	addi t3,t3,1
	sub	t0,t4,t3
	bgtz	t0,2b

	mv	t3,s1		/* get set up */
	mv	t4,s2
	mv	t6,t5
	prchr(0x0d)
	prchr(0x7c)
3:
	lbu	t1, 0(t3)	/* loop to read and compare the test pattern*/
	beq	t6,t1,4f
	nop
	jal memerror
	nop
	j mbl
	nop
	
4:	addi t6,t6,1
	andi t6,t6,0x0ff
	addi t3,t3,1
	sub	t0,t4,t3
	bgtz	t0,3b
	j	mbl

mh:
	mv	a0,s0
	jal umon_conout
	prchr(0x20)
	mv 	a0,s1		/* echo the range */
	jal printreg
	prchr(0x2d)
	prchr(0x3e)
	mv 	a0,s2
	jal printreg
	prcrlf
	li	t5,0

mhl:
	jal kb_wait
	addi t5,t5,1
	li t1, 0x0ffff
	and	t5,t5,t1
	mv	t3,s1		/* get set up */
	mv	t4,s2
	mv	t6,t5
	prchr(0x0d)
	prchr(0x2d)
2:
	sh	t6,0(t3)	/* loop to write the test pattern */
	addi t6,t6,1
	li t1, 0x0ffff
	and	t6,t6,t1
	addi t3,t3,2
	sub	t0,t4,t3
	bgtz	t0,2b

	mv	t3,s1		/* get set up */
	mv	t4,s2
	mv	t6,t5
	prchr(0x0d)
	prchr(0x7c)
3:
	lhu	t1,0(t3)	/* loop to read and compare the test pattern*/
	beq	t6,t1,4f
	nop
	jal memerror
	nop
	j mhl
	nop
	
4:	addi t6,t6,1
	li t1, 0x0ffff
	and	t6,t6,t1
	addi t3,t3,2
	sub	t0,t4,t3
	bgtz	t0,3b
	j	mhl

mw:
	mv	a0,s0
	jal umon_conout
	mv ra, zero
	prchr(0x20)
	mv 	a0,s1		/* echo the range */
	jal printreg
	mv ra, zero
	prchr(0x2d)
	prchr(0x3e)
	mv 	a0,s2
	jal printreg
	prcrlf
	li	t5,0

mwl:
	jal kb_wait
	addi t5,t5,1
	mv	t3,s1		/* get set up */
	mv	t4,s2
	mv	t6,t5
	prchr(0x0d)
	prchr(0x2d)
2:
	sw	t6,0(t3)	/* loop to write the test pattern */
	addi t6,t6,1
	addi t3,t3,4
	sub	t0,t4,t3
	bgtz	t0,2b

	mv	t3,s1		/* get set up */
	mv	t4,s2
	mv	t6,t5
	prchr(0x0d)
	prchr(0x7c)
3:
	lwu	t1,0(t3)	/* loop to read and compare the test pattern*/
	beq	t6,t1,4f
	nop
	jal memerror
	nop
	j mwl
	nop	
4:	addi t6,t6,1
	addi t3,t3,4
	sub	t0,t4,t3
	bgtz	t0,3b
	j	mwl


memerror:
	and t0,s6,1		/* test quiet flag */
	beq	t0,zero,1f
	jr	ra		/* quiet please!!!! */
1:
	save
/* 	prstr("Error at ") */
	la t3, errotatstring
1:	lb	a0,0(t3)
	beq	a0,zero,2f
	jal umon_conout
	addi t3, t3,1
	j	1b
2:

	mv	a0,t3
	jal printreg

/*	prstr(" read ") */
	la t3, readstring
1:	lb	a0,0(t3)
	beq	a0,zero,2f
	jal umon_conout
	addi t3, t3,1
	j	1b
2:

	mv	a0,t1
	jal printreg

/*	prstr(" expected ") */
	la t3, expectedstring
1:	lb	a0,0(t3)
	beq	a0,zero,2f
	jal umon_conout
	addi t3, t3,1
	j	1b
2:

	mv	a0,t6
	jal printreg
	prcrlf
	jal kb_wait
	return


/****************************************************************/
/*  This code segment enters into an memory test loop.  The     */
/* range of the loop is specified by TOS (S2) and NOS (S1). This*/
/* test writes a word and immediately reads it to test tor	*/
/* refreash arbitration problems.  To catch an arbitration 	*/ 
/* problem set the logic analyzer to trigger on the branch to	*/ 
/* memerror.  The write or read that caused the problem will be	*/
/* close by.							*/
/****************************************************************/
GLOBAL(memrx)
	mv	a0,s0		/* Echo the command */
	jal umon_conout		
	prchr(0x20)
	mv 	a0,s1		/* echo the range */
	jal printreg 
/*	prchr(0x2d)
	prchr(0x3e) */
	mv 	a0,s2
	jal printreg
	prcrlf
	li	t6,0

memrxl:
	jal kb_wait
	addi t6,t6,1
	mv	t3,s1		/* get set up */
	mv	t4,s2
	prchr(0x0d)
	prchr(0x2d)
	prchr(0x0d)
	prchr(0x7c)
2:
	sw	t6,0(t3)	/*  write the test pattern */
	lw	t1,0(t3)	/*  read and compare the test pattern*/
	beq	t6,t1,4f
	jal memerror
	j memrxl
	nop
	
4:	addi t6,t6,1
	addi t3,t3,4
	sub	t0,t4,t3
	bgtz	t0,2b

	j	memrxl


trap_entry:
	la t3, trapentrystring
1:	lb	a0,0(t3)
	beq	a0,zero,2f
	jal umon_conout
	addi t3, t3,1
	j	1b
2:
	j 2b


