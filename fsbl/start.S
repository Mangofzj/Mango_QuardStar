/*
 * FSBL — First Stage Boot Loader。
 * 从 Parallel NOR Flash (0x20000000) 启动，将 OpenSBI 固件和设备树搬到 DDR 后跳转执行。
 * 只有 hart 0 执行加载，其余 hart 自旋等待 OpenSBI 唤醒。
 *
 * Parallel NOR Flash 布局：
 *   偏移 0x80000   sbi.dtb
 *   偏移 0x200000  fw_jump.bin
 *
 * Copyright (c) 2026-2027 Mango <13084743591@163.com>
 * SPDX-License-Identifier: GPL-2.0-or-later
 */

/* 从 Parallel NOR Flash 复制数据到 DDR。
 * a0 → 源地址，a1 → 目标地址，a2 → 结束地址，按 4 字节逐字搬运。
 */
.macro load_data, _src_start, _dst_start, _dst_end
    bgeu    \_dst_start, \_dst_end, 2f
1:
    lw      t0, (\_src_start)
    sw      t0, (\_dst_start)
    addi    \_src_start, \_src_start, 4
    addi    \_dst_start, \_dst_start, 4
    bltu    \_dst_start, \_dst_end, 1b
2:
.endm

.section .text
.globl _start
.type _start, @function

/*
 * 入口：hart 0 加载 OpenSBI 与设备树，其余 hart 自旋等待。
 */
_start:
    csrr    s0, mhartid
    bnez    s0, _loop

    /* 加载 fw_jump.bin：Parallel NOR Flash 0x20200000 → DDR 0xBFF80000（512KB） */
    li      a0, 0x202
    slli    a0, a0, 20
    li      a1, 0xbff
    slli    a1, a1, 20
    li      t2, 0x800
    slli    t2, t2, 8
    add     a1, a1, t2  // a1 = 0xBFF80000
    add     a2, a1, t2  // a2 = 0xC0000000
    load_data    a0, a1, a2

    /* 加载 sbi.dtb：Parallel NOR Flash 0x20080000 → DDR 0xBFF00000（512KB） */
    li      a0, 0x2008
    slli    a0, a0, 16  // a0 = 0x20080000
    li      a1, 0xbff
    slli    a1, a1, 20  // a1 = 0xBFF00000
    add     a2, a1, t2  // a2 = 0xBFF80000
    load_data    a0, a1, a2

    /* 设置参数跳转 OpenSBI：a0 = hartid，a1 = DTB 地址 */
    mv      a0, s0
    li      a1, 0xbff
    slli    a1, a1, 20  // a1 = 0xBFF00000
    li      t0, 0xbff
    slli    t0, t0, 20
    add     t0, t0, t2  // t0 = 0xBFF80000
    jr      t0

_loop:
    j       _loop

.end
