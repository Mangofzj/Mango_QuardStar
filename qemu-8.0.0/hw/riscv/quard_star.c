/*
 * QEMU RISC-V Quard Star Board — 板卡初始化。
 *
 * @brief 职责：CPU 创建、内存映射、中断控制器、串口、pflash、复位向量。
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
#include "hw/nvram/fw_cfg.h"
#include "sysemu/device_tree.h"
#include "sysemu/sysemu.h"

/* CPU 总数 */
#define QUARD_STAR_CPUS_TOTAL \
    (QUARD_STAR_MANAGEMENT_CPU_COUNT + QUARD_STAR_COMPUTE_CPU_COUNT)

/* 内存地址映射 */
static const MemMapEntry quard_star_memmap[] = {
    [QUARD_STAR_MROM]  = { 0x00000000, 0x20000 },  // 128KB Mask ROM
    [QUARD_STAR_SRAM]  = { 0x00020000, 0xe0000 },  // 896KB SRAM
    [QUARD_STAR_CLINT] = { 0x02000000, 0x10000 },  // ACLINT
    [QUARD_STAR_PLIC]  = { 0x0c000000, 0x4000000 },  // PLIC
    [QUARD_STAR_UART0] = { 0x10000000, 0x1000 },  // 串口 0
    [QUARD_STAR_UART1] = { 0x10001000, 0x1000 },  // 串口 1
    [QUARD_STAR_UART2] = { 0x10002000, 0x1000 },  // 串口 2
    [QUARD_STAR_VIRTIO0] = { 0x10100000, 0x1000 },  // virtio-mmio 0
    [QUARD_STAR_VIRTIO1] = { 0x10101000, 0x1000 },  // virtio-mmio 1
    [QUARD_STAR_VIRTIO2] = { 0x10102000, 0x1000 },  // virtio-mmio 2
    [QUARD_STAR_VIRTIO3] = { 0x10103000, 0x1000 },  // virtio-mmio 3
    [QUARD_STAR_VIRTIO4] = { 0x10104000, 0x1000 },  // virtio-mmio 4
    [QUARD_STAR_VIRTIO5] = { 0x10105000, 0x1000 },  // virtio-mmio 5
    [QUARD_STAR_VIRTIO6] = { 0x10106000, 0x1000 },  // virtio-mmio 6
    [QUARD_STAR_VIRTIO7] = { 0x10107000, 0x1000 },  // virtio-mmio 7
    [QUARD_STAR_FW_CFG] = { 0x10108000, 0x18 },  // fw_cfg
    [QUARD_STAR_FLASH] = { 0x20000000, 0x2000000 },  // pflash 32MB
    [QUARD_STAR_DRAM]  = { 0x80000000, 0x0 },  // DDR，大小由 -m 决定
};

/**
 * @brief 创建 pflash 设备并关联到 -drive if=pflash
 * @note  属性和别名分别用于配置 flash 参数及暴露给命令行
 * @param s             板卡状态
 * @param name          设备名
 * @param alias_prop_name  别名属性名
 * @return pflash 设备指针
 */
static PFlashCFI01 *quard_star_flash_create(QuardStarState *s,
                                            const char *name,
                                            const char *alias_prop_name)
{
    DeviceState *dev = qdev_new(TYPE_PFLASH_CFI01);

    qdev_prop_set_uint64(dev, "sector-length", QUARD_STAR_FLASH_SECTOR_SIZE);
    qdev_prop_set_uint8(dev, "width", 4);
    qdev_prop_set_uint8(dev, "device-width", 2);
    qdev_prop_set_bit(dev, "big-endian", false);
    qdev_prop_set_uint16(dev, "id0", 0x89);
    qdev_prop_set_uint16(dev, "id1", 0x18);
    qdev_prop_set_uint16(dev, "id2", 0x00);
    qdev_prop_set_uint16(dev, "id3", 0x00);
    qdev_prop_set_string(dev, "name", name);

    object_property_add_child(OBJECT(s), name, OBJECT(dev));
    object_property_add_alias(OBJECT(s), alias_prop_name,
                              OBJECT(dev), "drive");

    return PFLASH_CFI01(dev);
}

/**
 * @brief 将 pflash 映射到系统地址空间
 * @note  设置 block 数量后 realize，再挂载 MMIO 区域
 * @param flash  pflash 设备
 * @param base   基地址
 * @param size   总大小
 * @param sysmem 系统地址空间
 * @return 无
 */
static void quard_star_flash_map(PFlashCFI01 *flash,
                                 hwaddr base, hwaddr size,
                                 MemoryRegion *sysmem)
{
    DeviceState *dev = DEVICE(flash);

    assert(QEMU_IS_ALIGNED(size, QUARD_STAR_FLASH_SECTOR_SIZE));
    assert(size / QUARD_STAR_FLASH_SECTOR_SIZE <= UINT32_MAX);
    qdev_prop_set_uint32(dev, "num-blocks", size / QUARD_STAR_FLASH_SECTOR_SIZE);
    sysbus_realize_and_unref(SYS_BUS_DEVICE(dev), &error_fatal);

    memory_region_add_subregion(sysmem, base,
                                sysbus_mmio_get_region(SYS_BUS_DEVICE(dev), 0));
}

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
 * @brief 创建 8 组 virtio-mmio 设备
 * @note  每组占用 4KB MMIO 空间，中断依次连到 PLIC 1-8 号源
 * @param machine 机器状态
 * @return 无
 */
static void quard_star_virtio_mmio_create(MachineState *machine)
{
    QuardStarState *s = QUARD_STAR_MACHINE(machine);

    sysbus_create_simple("virtio-mmio",
        quard_star_memmap[QUARD_STAR_VIRTIO0].base,
        qdev_get_gpio_in(DEVICE(s->plic), QUARD_STAR_VIRTIO0_IRQ));
    sysbus_create_simple("virtio-mmio",
        quard_star_memmap[QUARD_STAR_VIRTIO1].base,
        qdev_get_gpio_in(DEVICE(s->plic), QUARD_STAR_VIRTIO1_IRQ));
    sysbus_create_simple("virtio-mmio",
        quard_star_memmap[QUARD_STAR_VIRTIO2].base,
        qdev_get_gpio_in(DEVICE(s->plic), QUARD_STAR_VIRTIO2_IRQ));
    sysbus_create_simple("virtio-mmio",
        quard_star_memmap[QUARD_STAR_VIRTIO3].base,
        qdev_get_gpio_in(DEVICE(s->plic), QUARD_STAR_VIRTIO3_IRQ));
    sysbus_create_simple("virtio-mmio",
        quard_star_memmap[QUARD_STAR_VIRTIO4].base,
        qdev_get_gpio_in(DEVICE(s->plic), QUARD_STAR_VIRTIO4_IRQ));
    sysbus_create_simple("virtio-mmio",
        quard_star_memmap[QUARD_STAR_VIRTIO5].base,
        qdev_get_gpio_in(DEVICE(s->plic), QUARD_STAR_VIRTIO5_IRQ));
    sysbus_create_simple("virtio-mmio",
        quard_star_memmap[QUARD_STAR_VIRTIO6].base,
        qdev_get_gpio_in(DEVICE(s->plic), QUARD_STAR_VIRTIO6_IRQ));
    sysbus_create_simple("virtio-mmio",
        quard_star_memmap[QUARD_STAR_VIRTIO7].base,
        qdev_get_gpio_in(DEVICE(s->plic), QUARD_STAR_VIRTIO7_IRQ));
}

/**
 * @brief 创建 fw_cfg 设备并内置 CPU 数量
 * @note  通过 -fw_cfg 选项可向虚拟机传递自定义参数
 * @param machine 机器状态
 * @return 无
 */
static void quard_star_fw_cfg_create(MachineState *machine)
{
    QuardStarState *s = QUARD_STAR_MACHINE(machine);

    s->fw_cfg = fw_cfg_init_mem_wide(quard_star_memmap[QUARD_STAR_FW_CFG].base + 8,
                                     quard_star_memmap[QUARD_STAR_FW_CFG].base, 8,
                                     quard_star_memmap[QUARD_STAR_FW_CFG].base + 16,
                                     &address_space_memory);
    fw_cfg_add_i16(s->fw_cfg, FW_CFG_NB_CPUS, (uint16_t)machine->smp.cpus);
    rom_set_fw(s->fw_cfg);
}

/**
 * @brief Quard Star 板卡初始化入口
 * @note  依次初始化 MROM、SRAM、DRAM，创建 CPU Cluster、CLINT、PLIC、串口、pflash、virtio、fw_cfg
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
    char *plic_hart_config;
    size_t plic_hart_config_len;
    int i;

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

    /* CLINT: ACLINT 软件中断 + 定时器，覆盖全部 8 个 hart */
    riscv_aclint_swi_create(quard_star_memmap[QUARD_STAR_CLINT].base,
                            0, QUARD_STAR_CPUS_TOTAL, false);
    riscv_aclint_mtimer_create(
        quard_star_memmap[QUARD_STAR_CLINT].base + RISCV_ACLINT_SWI_SIZE,
        quard_star_memmap[QUARD_STAR_CLINT].size - RISCV_ACLINT_SWI_SIZE,
        0, QUARD_STAR_CPUS_TOTAL, RISCV_ACLINT_DEFAULT_MTIMECMP,
        RISCV_ACLINT_DEFAULT_MTIME, RISCV_ACLINT_DEFAULT_TIMEBASE_FREQ, true);

    /* PLIC：管理外设中断，全部 hart 共享 */
    plic_hart_config_len = (strlen(QUARD_STAR_PLIC_HART_CONFIG) + 1)
                           * QUARD_STAR_CPUS_TOTAL;
    plic_hart_config = g_malloc0(plic_hart_config_len);
    for (i = 0; i < QUARD_STAR_CPUS_TOTAL; i++) {
        if (i != 0) {
            strncat(plic_hart_config, ",", plic_hart_config_len);
        }
        strncat(plic_hart_config, QUARD_STAR_PLIC_HART_CONFIG,
                plic_hart_config_len);
        plic_hart_config_len -= (strlen(QUARD_STAR_PLIC_HART_CONFIG) + 1);
    }
    s->plic = sifive_plic_create(
        quard_star_memmap[QUARD_STAR_PLIC].base,
        plic_hart_config, QUARD_STAR_CPUS_TOTAL, 0,
        QUARD_STAR_PLIC_NUM_SOURCES,
        QUARD_STAR_PLIC_NUM_PRIORITIES,
        QUARD_STAR_PLIC_PRIORITY_BASE,
        QUARD_STAR_PLIC_PENDING_BASE,
        QUARD_STAR_PLIC_ENABLE_BASE,
        QUARD_STAR_PLIC_ENABLE_STRIDE,
        QUARD_STAR_PLIC_CONTEXT_BASE,
        QUARD_STAR_PLIC_CONTEXT_STRIDE,
        quard_star_memmap[QUARD_STAR_PLIC].size);
    g_free(plic_hart_config);

    /* 串口：三个 NS16550A，中断连到 PLIC */
    serial_mm_init(system_memory, quard_star_memmap[QUARD_STAR_UART0].base,
                   0, qdev_get_gpio_in(DEVICE(s->plic), QUARD_STAR_UART0_IRQ),
                   399193, serial_hd(0), DEVICE_LITTLE_ENDIAN);
    serial_mm_init(system_memory, quard_star_memmap[QUARD_STAR_UART1].base,
                   0, qdev_get_gpio_in(DEVICE(s->plic), QUARD_STAR_UART1_IRQ),
                   399193, serial_hd(1), DEVICE_LITTLE_ENDIAN);
    serial_mm_init(system_memory, quard_star_memmap[QUARD_STAR_UART2].base,
                   0, qdev_get_gpio_in(DEVICE(s->plic), QUARD_STAR_UART2_IRQ),
                   399193, serial_hd(2), DEVICE_LITTLE_ENDIAN);

    /* pflash：固件载体，通过 -drive if=pflash 加载 */
    s->flash = quard_star_flash_create(s, "quard-star.flash0", "pflash0");
    pflash_cfi01_legacy_drive(s->flash, drive_get(IF_PFLASH, 0, 0));
    quard_star_flash_map(s->flash, quard_star_memmap[QUARD_STAR_FLASH].base,
                         quard_star_memmap[QUARD_STAR_FLASH].size,
                         system_memory);

    /* virtio：8 组 virtio-mmio 设备，后续配置为块设备、网卡等 */
    quard_star_virtio_mmio_create(machine);

    /* fw_cfg：向虚拟机传递参数的通道 */
    quard_star_fw_cfg_create(machine);

    /* 复位向量：跳转到 pflash 起始地址 */
    quard_star_setup_rom_reset_vec(machine, &s->c_cpus,
                                   quard_star_memmap[QUARD_STAR_FLASH].base,
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
    mc->max_cpus = QUARD_STAR_CPUS_TOTAL;
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
    .name          = TYPE_RISCV_QUARD_STAR_MACHINE,
    .parent        = TYPE_MACHINE,
    .class_init    = quard_star_machine_class_init,
    .instance_init = quard_star_machine_instance_init,
    .instance_size = sizeof(QuardStarState),
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
