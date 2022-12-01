#include "umain.S"
/****************************************************************/
/*  This code segment gets and puts characters to a terminal.   */
/* It should be the only code to be modified with each new      */
/* design. 							*/		
/* Also has display routines at the bottom of this section      */
/****************************************************************/

/* .align 8 */

.global date
/* .global time */
date:	
	.string __DATE__ 
/*
time:
	.string __TIME__
*/
/* .align 8 */

/* 	.set noreorder */

GLOBAL(init_uart)
	li	a0,UART_BASE
	sb	zero,UART_IER(a0)	/*  disable interrupts */


	li	t1,0x80
	sb	t1,UART_LCR(a0)		/*  set DLAB (divisor latch access bit) to hi */

	/* Divisor at 100Mhz for CR116 = 5 for a Baud Rate of 1,250,00 */
	/* Change this for CR3664 .. SIM=1, real world = ? */

	li	t1,0x05		/*  Change based on the crystal/baud rate. &&&&&*/
	and	t1,t1,0xff		/*  first drop the upper byte of the half word */
	sb	t1,UART_DLL(a0)	/*  store divisor LSB in DLL */

	li	t1,0x01				/*  Change based on the crystal/baud rate. &&&&&*/
	srl	t1,t1,8				/*  shift right 8 bits to move upper byte into lower byte */
	sb	t1,UART_DLM(a0)		/*  store divisor MSB in DLM */
	
	li	t1,UART_8N1			/*  load t1 with 8 bits, no parity, 1 stop bit */
	sb	t1,UART_LCR(a0)		/*  write into LCR */
							/* This will also set the UART back to normal operations */

	li	t1,0x07		/*  enable fifos and clear them */
				/*  fifo mode enable, rcv fifo clear, xmt fifo clear, */
				/*  trigger interrupt for every byte (note: interrupts not used  */
	sb	t1,UART_FCR(a0)	/*  write to fifo control register */	

			
	li	t1, 0x00	/* Clear MCR bit 5 to disable Auto-RTS & Auto-CTS */
	sb	t1, UART_MCR(a0) 

	jr	ra		/* return to caller */
	nop



GLOBAL(umon_conin)
	li	t2,UART_BASE	/* load uart register base address */
1:	lb	t1,UART_LSR(t2)	/* fetch status */

	nop			/* kill some time */
	and	t1,t1,UART_DR	/* see if a key has been struck */
	beq	t1,zero,1b		

	lb	a0,UART_RBR(t2)	/* grab that char while its there */
	andi a0,a0,0x7f		/* mask it to 7 bits */
	jr	ra		/* return to caller */
	
GLOBAL(constat)
	li	t2,UART_BASE	/* load uart register base address */
	lb	t1,UART_LSR(t2)	/* fetch status */
	nop			/* kill some time */
	and	a0,t1,UART_DR	/* see if a key has been struck */
	jr	ra

GLOBAL(umon_conout)
	li	t2,UART_BASE	/* load uart register base address */
1:	lb	t1,UART_LSR(t2)	/* get that status one more time */
	nop			/* again - dont be in a rush */	
	and	t1,t1,UART_THRE	/* see if the transmitter is ready to */
				/* accept another char, i.e THRE indicator set*/
	beq	t1,zero,1b	/* branch if not ready */
	nop
	sb	a0,UART_THR(t2)	/* send the char to xmit buf, THR. */
	jr	ra		/* return to caller */
	nop

GLOBAL(print_number)	
	mv t3, ra
	mv t0, a0
	srli t0, t0, 0x04
	li t1, 0x0a
	bge	t0, t1, alpha
	nop
	addi t0, t0, 0x30
	mv t4, a0
	mv a0, t0
	jal umon_conout	
	nop
	j 	upper_char
	nop
alpha:
	addi t0,t0, 0x31
	mv t4, a0
	mv a0, t0
	jal umon_conout
	nop
upper_char:
	andi t4, t4, 0xf0
	srli t4, t4, 0x04
	li t1, 0x0a
	bge t4, t1, alpha2
	nop
	addi t4, t4, 0x30
	mv a0, t4
	jal umon_conout
	nop
	j print_done
	nop
alpha2:
	addi t4, t4, 0x31
	mv a0, t4
	jal umon_conout
	nop
print_done:

	mv ra, t3
	jr ra
	nop

datestring:
.string	"\n\rBuild Date: "
timesring:
.string "\n\rBuild Time: "
hellostring:
.string	"\n\ruMON V1.0"
promptstring:
.string " Type '^q' or 'q' to continue, '.' to terminate.\n\r"
foundstring:
.string "Found "
atstring:
.string " at "
patternstring:
.string " pattern "
errotatstring:
.string "Error at "
readstring:
.string " read "
expectedstring:
.string " expected "
addressstring:
.string " address "
datastring:
.string " data "
hartidstring:
.string " HartID "
trapentrystring:
.string "Trap Entry "

/* .string	"\n\ruMON Port to RISC-V Hondo: Marc Karasek V1.0 64Bit" */


/*
	la t3, addressstring
1:	lb	a0,0(t3)
	beq	a0,zero,2f
	jal umon_conout
	addi t3, t3,1
	j	1b
2:
	mv a0, s2
	jal print_number
	prcrlf
*/