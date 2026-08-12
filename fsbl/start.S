/*
 * FSBL — First Stage Boot Loader。
 * 从 pflash (0x20000000) 启动，向 UART0 打印 "Hello Quard Star Board!\n"
 * 后进入死循环。只有 hart 0 执行，其余 hart 自旋等待。
 *
 * Copyright (c) 2026-2027 Mango <13084743591@163.com>
 * SPDX-License-Identifier: GPL-2.0-or-later
 */

#define UART0_BASE 0x10000000  // UART0 MMIO 基址

.section .text
.globl _start
.type _start, @function

/*
 * 入口：只允许 hart 0 执行 I/O，其余 hart 自旋。
 * hart 0 将 hello_str 逐字节写入 UART0 数据寄存器。
 */
_start:
    /* 非 hart 0 的 CPU 进入死循环 */
    csrr    a0, mhartid
    bnez    a0, _loop

    /* hart 0：向 UART0 输出字符串 */
    la      t0, UART0_BASE
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
    .asciz    "Hello Quard Star Board!\n"

.end
