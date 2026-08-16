#!/bin/bash
# Quard Star — QEMU 启动脚本（ch6 设备树与 OpenSBI 加载运行）
# FSBL 从 Parallel NOR Flash 启动，加载 OpenSBI 与设备树到 DDR 后跳转执行。

SHELL_FOLDER=$(cd "$(dirname "$0")";pwd)

$SHELL_FOLDER/output/qemu/bin/qemu-system-riscv64 \
    -M quard-star \
    -m 1G \
    -smp 8 \
    -drive if=pflash,bus=0,unit=0,format=raw,file=$SHELL_FOLDER/output/fsbl/fw.bin \
    -nographic --parallel none
