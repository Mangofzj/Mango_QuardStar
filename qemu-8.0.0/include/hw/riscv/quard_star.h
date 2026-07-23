/*
 * QEMU RISC-V Quard Star Board
 *
 * @brief 双 Cluster 异构 RISC-V 板卡：7 核计算集群 + 1 核管理集群。
 * 启动链：Mask ROM → OpenSBI → U-Boot → Linux Kernel。
 *
 * Copyright (c) 2026-2027 Mango <13084743591@163.com>
 * SPDX-License-Identifier: GPL-2.0-or-later
 */

#ifndef HW_RISCV_QUARD_STAR__H
#define HW_RISCV_QUARD_STAR__H

#include "hw/block/flash.h"
#include "hw/cpu/cluster.h"
#include "hw/riscv/riscv_hart.h"
#include "hw/sysbus.h"

#define QUARD_STAR_MANAGEMENT_CPU_COUNT    1
#define QUARD_STAR_COMPUTE_CPU_COUNT       7

#define TYPE_RISCV_QUARD_STAR_MACHINE MACHINE_TYPE_NAME("quard-star")
typedef struct QuardStarState QuardStarState;
DECLARE_INSTANCE_CHECKER(QuardStarState, QUARD_STAR_MACHINE,
                         TYPE_RISCV_QUARD_STAR_MACHINE)

/* 板卡私有状态 */
struct QuardStarState {
    /*< private >*/
    MachineState parent;

    /*< public >*/
    CPUClusterState r_cluster;  // 管理集群（1 核，hartid 7）
    CPUClusterState c_cluster;  // 计算集群（7 核，hartid 0-6）
    RISCVHartArrayState r_cpus;
    RISCVHartArrayState c_cpus;
    DeviceState *plic;
    PFlashCFI01 *flash;
};

/* 内存映射索引 */
enum {
    QUARD_STAR_MROM,
    QUARD_STAR_SRAM,
    QUARD_STAR_CLINT,
    QUARD_STAR_PLIC,
    QUARD_STAR_UART0,
    QUARD_STAR_UART1,
    QUARD_STAR_UART2,
    QUARD_STAR_FLASH,
    QUARD_STAR_DRAM,
};

/* 外设中断号 */
enum {
    QUARD_STAR_UART0_IRQ   = 10,
    QUARD_STAR_UART1_IRQ   = 11,
    QUARD_STAR_UART2_IRQ   = 12,
};

#define QUARD_STAR_PLIC_HART_CONFIG    "MS"
#define QUARD_STAR_PLIC_NUM_SOURCES    127
#define QUARD_STAR_PLIC_NUM_PRIORITIES 7
#define QUARD_STAR_PLIC_PRIORITY_BASE  0x04
#define QUARD_STAR_PLIC_PENDING_BASE   0x1000
#define QUARD_STAR_PLIC_ENABLE_BASE    0x2000
#define QUARD_STAR_PLIC_ENABLE_STRIDE  0x80
#define QUARD_STAR_PLIC_CONTEXT_BASE   0x200000
#define QUARD_STAR_PLIC_CONTEXT_STRIDE 0x1000
#define QUARD_STAR_PLIC_SIZE(__num_context) \
    (QUARD_STAR_PLIC_CONTEXT_BASE + (__num_context) * QUARD_STAR_PLIC_CONTEXT_STRIDE)

#define QUARD_STAR_FLASH_SECTOR_SIZE (256 * KiB)

#endif /* HW_RISCV_QUARD_STAR__H */
