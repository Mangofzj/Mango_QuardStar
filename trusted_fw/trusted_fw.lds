/*
 * Trusted FW 链接脚本。
 *
 * 代码段放置在 DDR 0xBF800000，4MB 空间（tmem0 可信区）。
 * OpenSBI 加载后跳转到 _start 开始执行。
 *
 * Copyright (c) 2026-2027 Mango <13084743591@163.com>
 * SPDX-License-Identifier: GPL-2.0-or-later
 */

OUTPUT_ARCH("riscv")

ENTRY(_start)

MEMORY
{
    ddr (rxai!w) : ORIGIN = 0xBF800000, LENGTH = 4M
}

SECTIONS
{
    .text :
    {
        KEEP(*(.text))
    } >ddr

    .rodata :
    {
        KEEP(*(.rodata))
        KEEP(*(.rodata.*))
    } >ddr
}
