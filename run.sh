#!/bin/bash
# Quard Star — QEMU 启动脚本（ch7 OpenSBI Domain）
# FSBL 从 Parallel NOR Flash 启动，加载 OpenSBI、设备树与可信固件到 DDR 后跳转执行。
# 串口窗口：uart0（OpenSBI 日志）、uart2（可信固件打印）、monitor 各占一个 vc 终端窗口。

SHELL_FOLDER=$(cd "$(dirname "$0")";pwd)

$SHELL_FOLDER/output/qemu/bin/qemu-system-riscv64 \
    -M quard-star \
    -m 1G \
    -smp 8 \
    -drive if=pflash,bus=0,unit=0,format=raw,file=$SHELL_FOLDER/output/fsbl/fw.bin \
    --serial vc:1280x720 \
    --serial vc:1280x720 \
    --serial vc:1280x720 \
    --monitor vc:1280x720 \
    --parallel none
