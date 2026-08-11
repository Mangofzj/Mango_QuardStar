#!/bin/bash
# Quard Star — QEMU 启动脚本（ch4 FSBL 测试）
# FSBL 从 pflash 启动，向 UART0 打印 "Hello Quard Star Board!"。

SHELL_FOLDER=$(cd "$(dirname "$0")";pwd)

$SHELL_FOLDER/output/qemu/bin/qemu-system-riscv64 \
    -M quard-star \
    -m 1G \
    -smp 8 \
    -drive if=pflash,bus=0,unit=0,format=raw,file=$SHELL_FOLDER/output/fsbl/fw.bin \
    -nographic --parallel none
