/* Copyright (c) 2020 CryptoCore LLC. */


#ifdef __ASSEMBLER__
#define _AC(X,Y)        X
#else
#define _AC(X,Y)        (X##Y)
#endif /* !__ASSEMBLER__*/

#define GLOBAL(name)      \
	.globl name;	 	 \
name:

#define LOCAL(name)      \
	.local name;	 	 \
name:


/*****************************
Gobal Defines
*****************************/
#define _zero		0x00000000
#define _128		0x00000080
#define _256		0x00000100
#define _512		0x00000200
#define _1K			0x00000400
#define _2K			0x00000800
#define _4K			0x00001000
#define _8K			0x00002000
#define _16K		0x00004000
#define _32K		0x00008000
#define _64K		0x00010000
#define _128K		0x00020000
#define _256K		0x00040000
#define _512K		0x00080000
#define _1M			0x00100000		
#define _2M			0x00200000
#define _4M			0x00400000
#define _8M			0x00800000
#define _16M		0x01000000
#define _32M		0x02000000
#define _64M		0x04000000
#define _128M		0x08000000
#define _256M		0x10000000
#define _512M		0x20000000
#define _1G			0x40000000
#define _2G			0x80000000

#define _2000nS		2000
#define _1400nS		1400
#define _1000nS		1000
#define _200nS		200
#define _80nS		80
#define _70nS		70
#define _40nS		40 
#define _20nS		20
#define _15nS		15
#define _10nS		10
#define _7800nS		7800 	/* 7.8 uS */
#define _120000nS	120000 	/* 120,000 nS */
#define _15625nS	15625 	/* 15.625 uS */
#define _3900nS		3900 	/* 3.9 uS */
#define _31300nS	31300 	/* 31.3 uS */
#define _62500nS	62500	/* 62.5 uS */
#define _125000nS	125000	/* 125 uS */

#define REG_OFFSET(n,m)	(m * n)
#define REG_32		4
#define REG_16		2
#define REG_8		1

#define UART0_CTRL_ADDR _AC(0x2EE00000,UL)
#define  UART_BASE UART0_CTRL_ADDR
#define UART0_CTRL_SIZE _AC(0x10,UL)

/* Register offsets */
#define UART_RBR	0x0000
#define UART_THR	0x0000
#define UART_IER	0x0001
#define UART_IIR	0x0002
#define UART_FCR	0x0002
#define UART_LCR	0x0003
#define UART_MCR	0x0004
#define UART_LSR	0x0005
#define UART_MSR	0x0006
#define UART_DLL	0x0000
#define UART_DLM	0x0001

#define UART_8N1	0x03
#define UART_7E2	0x1E
#define UART_DR		0x01
#define UART_THRE	0x20