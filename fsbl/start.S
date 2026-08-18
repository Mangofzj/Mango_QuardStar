/*
 * FSBL — First Stage Boot Loader。
 * 从 Parallel NOR Flash (0x20000000) 启动，将 OpenSBI 固件、设备树与可信固件搬到 DDR 后跳转 OpenSBI。
 * 所有 hart 均参与加载，非 0 hart 延时等待镜像搬运完成后再跳转。
 *
 * Parallel NOR Flash 布局：
 *   偏移 0x80000   quard_star_sbi.dtb
 *   偏移 0x200000  fw_jump.bin
 *   偏移 0x400000  trusted_fw.bin
 *
 * Copyright (c) 2026-2027 Mango <13084743591@163.com>
 * SPDX-License-Identifier: GPL-2.0-or-later
 */

/* 简单延时：非 0 hart 等待镜像搬运完成。
 * t1 为内层计数，t2 为外层计数，\count 为外层循环次数。
 */
.macro loop, count
    li      t1, 0xffff
    li      t2, \count
1:
    nop
    addi    t1, t1, -1
    bne     t1, x0, 1b
    li      t1, 0xffff
    addi    t2, t2, -1
    bne     t2, x0, 1b
.endm

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
 * 入口：加载 OpenSBI、设备树与可信固件到 DDR，再跳转 OpenSBI。
 */
_start:
    /* 加载 fw_jump.bin：Parallel NOR Flash 0x20200000 → DDR 0x80000000（2MB） */
    li      a0, 0x202
    slli    a0, a0, 20  // a0 = 0x20200000
    li      a1, 0x800
    slli    a1, a1, 20  // a1 = 0x80000000
    li      a2, 0x802
    slli    a2, a2, 20  // a2 = 0x80200000
    load_data    a0, a1, a2

    /* 加载 quard_star_sbi.dtb：Parallel NOR Flash 0x20080000 → DDR 0x82200000（512KB） */
    li      a0, 0x2008
    slli    a0, a0, 16  // a0 = 0x20080000
    li      a1, 0x822
    slli    a1, a1, 20  // a1 = 0x82200000
    li      a2, 0x8228
    slli    a2, a2, 16  // a2 = 0x82280000
    load_data    a0, a1, a2

    /* 加载 trusted_fw.bin：Parallel NOR Flash 0x20400000 → DDR 0xb0000000（4MB） */
    li      a0, 0x204
    slli    a0, a0, 20  // a0 = 0x20400000
    li      a1, 0xb00
    slli    a1, a1, 20  // a1 = 0xb0000000
    li      a2, 0xb04
    slli    a2, a2, 20  // a2 = 0xb0400000
    load_data    a0, a1, a2

    /* hart 0 直接跳转，其余 hart 延时等待镜像搬运完成后跳转 */
    csrr    a0, mhartid
    beq     a0, x0, _no_wait
    loop    0x1000
_no_wait:
    li      a1, 0x822
    slli    a1, a1, 20  // a1 = 0x82200000
    li      t0, 0x800
    slli    t0, t0, 20  // t0 = 0x80000000
    jr      t0

.end
