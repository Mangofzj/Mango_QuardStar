/*
 * Trusted FW — 可信域测试固件。
 * 由 OpenSBI 加载到 DDR 0xb0000000，在 trusted-domain（cpu7）中运行，
 * 向 UART2 打印 "Hello Quard Star Board!\r\n" 后进入死循环。
 *
 * Copyright (c) 2026-2027 Mango <13084743591@163.com>
 * SPDX-License-Identifier: GPL-2.0-or-later
 */

#define UART2_BASE 0x10002000  // UART2 MMIO 基址

.section .text
.globl _start
.type _start, @function

/*
 * 入口：向 UART2 逐字节输出字符串，打印完成后进入死循环。
 */
_start:
    /* 向 UART2 输出字符串 */
    la      t0, UART2_BASE
    la      t1, hello_str

_putc:
    lb      t2, 0(t1)
    beqz    t2, _loop
    sb      t2, 0(t0)
    addi    t1, t1, 1
    j       _putc

_loop:
    j       _loop

.section .rodata
hello_str:
    .asciz    "Hello Quard Star Board!\r\n"

.end
