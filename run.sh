#!/bin/bash
# Quard Star — QEMU 启动脚本（ch2 最小板卡验证）
# 运行后进入 QEMU monitor，输入 info registers 查看 CPU 状态，输入 q 退出。

SHELL_FOLDER=$(cd "$(dirname "$0")";pwd)

$SHELL_FOLDER/output/qemu/bin/qemu-system-riscv64 \
    -M quard-star \
    -m 1G \
    -smp 8 \
    -nographic --parallel none
