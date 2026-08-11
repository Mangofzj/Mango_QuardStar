/*
 * FSBL 链接脚本。
 *
 * 代码段放置在 pflash 起始地址 0x20000000，512KB 空间。
 * 复位向量跳转到这里后，CPU 从 _start 开始执行。
 *
 * Copyright (c) 2026-2027 Mango <13084743591@163.com>
 * SPDX-License-Identifier: GPL-2.0-or-later
 */

OUTPUT_ARCH("riscv")

ENTRY(_start)

MEMORY
{
    flash (rxai!w) : ORIGIN = 0x20000000, LENGTH = 512K
}

SECTIONS
{
    .text :
    {
        KEEP(*(.text))
    } >flash

    .rodata :
    {
        KEEP(*(.rodata))
        KEEP(*(.rodata.*))
    } >flash
}
