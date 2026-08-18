#!/bin/bash
# Quard Star — QEMU 启动脚本（ch7 OpenSBI Domain）
# FSBL 从 Parallel NOR Flash 启动，加载 OpenSBI、设备树与可信固件到 DDR 后跳转执行。
# 串口映射：uart0 → stdio（OpenSBI 日志），uart1 → null，uart2 → output/uart2.log（可信固件打印）。

SHELL_FOLDER=$(cd "$(dirname "$0")";pwd)

$SHELL_FOLDER/output/qemu/bin/qemu-system-riscv64 \
    -M quard-star \
    -m 1G \
    -smp 8 \
    -drive if=pflash,bus=0,unit=0,format=raw,file=$SHELL_FOLDER/output/fsbl/fw.bin \
    -serial stdio \
    -serial null \
    -serial file:$SHELL_FOLDER/output/uart2.log \
    -display none \
    --parallel none
