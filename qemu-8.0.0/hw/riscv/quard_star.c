/*
 * QEMU RISC-V Quard Star Board — 板卡初始化。
 *
 * @brief 职责：CPU 创建、内存映射、中断控制器、复位向量。
 *
 * Copyright (c) 2026-2027 Mango <13084743591@163.com>
 * SPDX-License-Identifier: GPL-2.0-or-later
 */

#include "qemu/osdep.h"
#include "qemu/units.h"
#include "qemu/error-report.h"
#include "qapi/error.h"
#include "hw/boards.h"
#include "hw/loader.h"
#include "hw/qdev-properties.h"
#include "hw/char/serial.h"
#include "target/riscv/cpu.h"
#include "hw/riscv/riscv_hart.h"
#include "hw/riscv/quard_star.h"
#include "hw/riscv/boot.h"
#include "hw/riscv/numa.h"
#include "hw/intc/riscv_aclint.h"
#include "hw/intc/sifive_plic.h"
#include "sysemu/device_tree.h"
#include "sysemu/sysemu.h"

/* 内存地址映射 */
static const MemMapEntry quard_star_memmap[] = {
    [QUARD_STAR_MROM]  = { 0x00000000,   0x20000 },  // 128KB Mask ROM
    [QUARD_STAR_SRAM]  = { 0x00020000,   0xe0000 },  // 896KB SRAM
    [QUARD_STAR_CLINT] = { 0x02000000,   0x10000 },  // ACLINT
    [QUARD_STAR_PLIC]  = { 0x0c000000, 0x4000000 },  // PLIC
    [QUARD_STAR_UART0] = { 0x10000000,    0x1000 },  // 串口 0
    [QUARD_STAR_DRAM]  = { 0x80000000,       0x0 },  // DDR，大小由 -m 决定
};

/**
 * @brief 将复位向量写入 Mask ROM
 * @note  CPU 复位后执行：读取 hartid → a0，设备树地址 → a1，跳转到 start_addr
 * @param machine       机器状态
 * @param harts         HART 数组（用于判断 32/64 位）
 * @param start_addr    跳转目标地址
 * @param rom_base      Mask ROM 基地址
 * @param rom_size      Mask ROM 大小
 * @param fdt_load_addr 设备树加载地址
 * @return 无
 */
static void quard_star_setup_rom_reset_vec(MachineState *machine,
                                RISCVHartArrayState *harts, hwaddr start_addr,
                                hwaddr rom_base, hwaddr rom_size,
                                uint32_t fdt_load_addr)
{
    uint32_t start_addr_hi32 = 0x00000000;

    if (!riscv_is_32bit(harts)) {
        start_addr_hi32 = start_addr >> 32;
    }

    uint32_t reset_vec[10] = {
        0x00000297,  // 1: auipc  t0, %pcrel_hi(fw_dyn)
        0x02828613,  // addi   a2, t0, %pcrel_lo(1b)
        0xf1402573,  // csrr   a0, mhartid
        0,
        0,
        0x00028067,  // jr     t0
        start_addr,  // start: .dword
        start_addr_hi32,  // start_addr 高 32 位
        fdt_load_addr,  // fdt_laddr: .dword
        0x00000000,  // fw_dyn:
    };

    if (riscv_is_32bit(harts)) {
        reset_vec[3] = 0x0202a583;  // lw  a1, 32(t0)
        reset_vec[4] = 0x0182a283;  // lw  t0, 24(t0)
    } else {
        reset_vec[3] = 0x0202b583;  // ld  a1, 32(t0)
        reset_vec[4] = 0x0182b283;  // ld  t0, 24(t0)
    }

    /* 按小端序写入 Mask ROM */
    for (int i = 0; i < ARRAY_SIZE(reset_vec); i++) {
        reset_vec[i] = cpu_to_le32(reset_vec[i]);
    }
    rom_add_blob_fixed_as("mrom.reset", reset_vec, sizeof(reset_vec),
                          rom_base, &address_space_memory);
}

/**
 * @brief 创建两个 CPU Cluster：计算集群（7 核）+ 管理集群（1 核）
 * @note  计算集群 hartid 0-6，管理集群 hartid 7
 * @param machine 机器状态
 * @return 无
 */
static void quard_star_cpu_create(MachineState *machine)
{
    QuardStarState *s = QUARD_STAR_MACHINE(machine);

    /* 计算集群：hartid 0-6 */
    object_initialize_child(OBJECT(machine), "c-cluster",
                            &s->c_cluster, TYPE_CPU_CLUSTER);
    qdev_prop_set_uint32(DEVICE(&s->c_cluster), "cluster-id", 0);
    object_initialize_child(OBJECT(&s->c_cluster), "c-cpus",
                            &s->c_cpus, TYPE_RISCV_HART_ARRAY);
    object_property_set_str(OBJECT(&s->c_cpus), "cpu-type",
                            machine->cpu_type, &error_abort);
    object_property_set_int(OBJECT(&s->c_cpus), "hartid-base",
                            0, &error_abort);
    object_property_set_int(OBJECT(&s->c_cpus), "num-harts",
                            QUARD_STAR_COMPUTE_CPU_COUNT, &error_abort);
    object_property_set_int(OBJECT(&s->c_cpus), "resetvec",
                            quard_star_memmap[QUARD_STAR_MROM].base,
                            &error_abort);
    sysbus_realize(SYS_BUS_DEVICE(&s->c_cpus), &error_fatal);
    qdev_realize(DEVICE(&s->c_cluster), NULL, &error_abort);

    /* 管理集群：hartid 7 */
    object_initialize_child(OBJECT(machine), "r-cluster",
                            &s->r_cluster, TYPE_CPU_CLUSTER);
    qdev_prop_set_uint32(DEVICE(&s->r_cluster), "cluster-id", 1);
    object_initialize_child(OBJECT(&s->r_cluster), "r-cpus",
                            &s->r_cpus, TYPE_RISCV_HART_ARRAY);
    object_property_set_str(OBJECT(&s->r_cpus), "cpu-type",
                            machine->cpu_type, &error_abort);
    object_property_set_int(OBJECT(&s->r_cpus), "hartid-base",
                            7, &error_abort);
    object_property_set_int(OBJECT(&s->r_cpus), "num-harts",
                            QUARD_STAR_MANAGEMENT_CPU_COUNT, &error_abort);
    object_property_set_int(OBJECT(&s->r_cpus), "resetvec",
                            quard_star_memmap[QUARD_STAR_MROM].base,
                            &error_abort);
    sysbus_realize(SYS_BUS_DEVICE(&s->r_cpus), &error_fatal);
    qdev_realize(DEVICE(&s->r_cluster), NULL, &error_abort);
}

/**
 * @brief Quard Star 板卡初始化入口
 * @note  依次初始化 MROM、SRAM、DRAM 内存区域，创建 CPU Cluster，设置复位向量
 * @param machine 机器状态
 * @return 无
 */
static void quard_star_machine_init(MachineState *machine)
{
    QuardStarState *s = QUARD_STAR_MACHINE(machine);
    MemoryRegion *system_memory = get_system_memory();
    MemoryRegion *mask_rom = g_new(MemoryRegion, 1);
    MemoryRegion *sram_mem = g_new(MemoryRegion, 1);
    MemoryRegion *main_mem = g_new(MemoryRegion, 1);

    /* MROM */
    memory_region_init_rom(mask_rom, NULL, "riscv_quard_star_board.mrom",
                           quard_star_memmap[QUARD_STAR_MROM].size, &error_fatal);
    memory_region_add_subregion(system_memory,
                                quard_star_memmap[QUARD_STAR_MROM].base, mask_rom);

    /* SRAM */
    memory_region_init_ram(sram_mem, NULL, "riscv_quard_star_board.sram",
                           quard_star_memmap[QUARD_STAR_SRAM].size, &error_fatal);
    memory_region_add_subregion(system_memory,
                                quard_star_memmap[QUARD_STAR_SRAM].base, sram_mem);

    /* DRAM */
    memory_region_init_ram(main_mem, NULL, "riscv_quard_star_board.dram",
                           machine->ram_size, &error_fatal);
    memory_region_add_subregion(system_memory,
                                quard_star_memmap[QUARD_STAR_DRAM].base, main_mem);

    /* CPU */
    quard_star_cpu_create(machine);

    /* Reset vector: 跳转到 MROM 起始地址 0x00000000 */
    quard_star_setup_rom_reset_vec(machine, &s->c_cpus, 0x00000000,
                                   quard_star_memmap[QUARD_STAR_MROM].base,
                                   quard_star_memmap[QUARD_STAR_MROM].size,
                                   0x0);
}

/**
 * @brief 板卡类初始化：设置描述、CPU 数量、初始化入口
 * @note  min_cpus 与 max_cpus 均固定为 8，不支持动态调整
 * @param oc   对象类
 * @param data 用户数据
 * @return 无
 */
static void quard_star_machine_class_init(ObjectClass *oc, void *data)
{
    MachineClass *mc = MACHINE_CLASS(oc);

    mc->desc = "RISC-V Quard Star Board";
    mc->init = quard_star_machine_init;
    mc->max_cpus = QUARD_STAR_MANAGEMENT_CPU_COUNT + QUARD_STAR_COMPUTE_CPU_COUNT;
    mc->min_cpus = mc->max_cpus;
    mc->default_cpu_type = TYPE_RISCV_CPU_BASE;
}

/**
 * @brief 板卡实例初始化，当前无操作
 * @note  无
 * @param obj 对象实例
 * @return 无
 */
static void quard_star_machine_instance_init(Object *obj)
{
}

/* 板卡类型信息 */
static const TypeInfo quard_star_machine_typeinfo = {
    .name           = TYPE_RISCV_QUARD_STAR_MACHINE,
    .parent         = TYPE_MACHINE,
    .class_init     = quard_star_machine_class_init,
    .instance_init  = quard_star_machine_instance_init,
    .instance_size  = sizeof(QuardStarState),
};

/**
 * @brief 向 QEMU 注册板卡类型
 * @note  通过 type_init 宏在 QEMU 启动时自动调用
 * @param 无
 * @return 无
 */
static void quard_star_machine_init_register_types(void)
{
    type_register_static(&quard_star_machine_typeinfo);
}
type_init(quard_star_machine_init_register_types)
