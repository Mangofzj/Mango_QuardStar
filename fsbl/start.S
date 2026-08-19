/*
 * FSBL — First Stage Boot Loader。
 * 从 Parallel NOR Flash (0x20000000) 启动，将 OpenSBI 固件、设备树、可信固件
 * 与 U-Boot 搬到 DDR 后跳转 OpenSBI。
 * 仅 core0 参与加载，其余 hart 轮询 _pen 标志等待镜像搬运完成后一起跳转。
 *
 * Parallel NOR Flash 布局：
 *   偏移 0x80000   quard_star_sbi.dtb
 *   偏移 0x100000  quard_star_uboot.dtb
 *   偏移 0x200000  fw_jump.bin
 *   偏移 0x400000  trusted_fw.bin
 *   偏移 0x800000  u-boot.bin
 *
 * DDR 加载布局：
 *   fw_jump.bin   → 0xbff80000
 *   sbi.dtb       → 0xbff00000
 *   trusted_fw    → 0xbf800000
 *   uboot.dtb     → 0xb0000000
 *   u-boot.bin    → 0xb0200000
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

/* 多核同步标志：位于 SRAM 可写区（见 fsbl.lds 的 .data 段）。
 * core0 置 1 后搬运镜像，搬运完成置 0 释放其余 hart。
 */
.section .data
.globl _pen
.type _pen, @object
_pen:
    .word   1

.section .text
.globl _start
.type _start, @function

/*
 * 入口：core0 搬运各镜像到 DDR，其余 hart 轮询 _pen 后一起跳转 OpenSBI。
 */
_start:
    csrr    a0, mhartid
    beq     a0, x0, _no_wait

_loop:
    loop    0x1000
    la      t0, _pen
    lw      t0, 0(t0)
    beq     t0, x0, _run
    j       _loop

_no_wait:
    la      t0, _pen
    li      t1, 1
    sw      t1, 0(t0)

    /* 加载 fw_jump.bin：Parallel NOR Flash 0x20200000 → DDR 0xbff80000（512KB） */
    li      a0, 0x202
    slli    a0, a0, 20  // a0 = 0x20200000
    li      a1, 0xbff
    slli    a1, a1, 20  // a1 = 0xbff00000
    li      a2, 0x800
    slli    a2, a2, 8   // a2 = 0x80000
    add     a1, a1, a2  // a1 = 0xbff80000
    add     a2, a1, a2  // a2 = 0xc0000000
    load_data    a0, a1, a2

    /* 加载 quard_star_sbi.dtb：Parallel NOR Flash 0x20080000 → DDR 0xbff00000（512KB） */
    li      a0, 0x2008
    slli    a0, a0, 16  // a0 = 0x20080000
    li      a1, 0xbff
    slli    a1, a1, 20  // a1 = 0xbff00000
    li      a2, 0x800
    slli    a2, a2, 8   // a2 = 0x80000
    add     a2, a1, a2  // a2 = 0xbff80000
    load_data    a0, a1, a2

    /* 加载 trusted_fw.bin：Parallel NOR Flash 0x20400000 → DDR 0xbf800000（4MB） */
    li      a0, 0x204
    slli    a0, a0, 20  // a0 = 0x20400000
    li      a1, 0xbf8
    slli    a1, a1, 20  // a1 = 0xbf800000
    li      a2, 0xbfc
    slli    a2, a2, 20  // a2 = 0xbfc00000
    load_data    a0, a1, a2

    /* 加载 quard_star_uboot.dtb：Parallel NOR Flash 0x20100000 → DDR 0xb0000000（512KB） */
    li      a0, 0x201
    slli    a0, a0, 20  // a0 = 0x20100000
    li      a1, 0xb00
    slli    a1, a1, 20  // a1 = 0xb0000000
    li      a2, 0x800
    slli    a2, a2, 8   // a2 = 0x80000
    add     a2, a1, a2  // a2 = 0xb0080000
    load_data    a0, a1, a2

    /* 加载 u-boot.bin：Parallel NOR Flash 0x20800000 → DDR 0xb0200000（4MB） */
    li      a0, 0x208
    slli    a0, a0, 20  // a0 = 0x20800000
    li      a1, 0xb02
    slli    a1, a1, 20  // a1 = 0xb0200000
    li      a2, 0xb06
    slli    a2, a2, 20  // a2 = 0xb0600000
    load_data    a0, a1, a2

_run:
    csrr    a0, mhartid
    li      a1, 0xbff
    slli    a1, a1, 20  // a1 = 0xbff00000（sbi.dtb 地址）
    li      t0, 0x800
    slli    t0, t0, 8   // t0 = 0x80000
    add     t0, a1, t0  // t0 = 0xbff80000（OpenSBI 地址）
    la      t1, _pen
    sw      x0, 0(t1)   // _pen = 0，释放其余 hart
    jr      t0

.end
