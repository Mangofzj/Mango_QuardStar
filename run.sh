#!/bin/bash
# Quard Star — QEMU 启动脚本（ch4 ZSBL 测试）
# ZSBL 从 pflash 启动，向 UART0 打印 "Hello Quard Star board!"。

SHELL_FOLDER=$(cd "$(dirname "$0")";pwd)

$SHELL_FOLDER/output/qemu/bin/qemu-system-riscv64 \
    -M quard-star \
    -m 1G \
    -smp 8 \
    -drive if=pflash,bus=0,unit=0,format=raw,file=$SHELL_FOLDER/output/zsbl/fw.bin \
    -nographic --parallel none
