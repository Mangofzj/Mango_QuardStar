#!/bin/bash
# Quard Star — QEMU 启动脚本（ch10 virtio/fw_cfg）
# FSBL 从 Parallel NOR Flash 启动，加载 OpenSBI、设备树与可信固件到 DDR 后跳转执行。
# 串口窗口：uart0（OpenSBI 日志）、uart2（可信固件打印）、monitor 各占一个 vc 终端窗口。

SHELL_FOLDER=$(cd "$(dirname "$0")";pwd)

# 生成空的 rootfs 镜像（ch14 才填充真正根文件系统）
if [ ! -f "$SHELL_FOLDER/output/rootfs/rootfs.img" ]; then
    mkdir -p "$SHELL_FOLDER/output/rootfs"
    dd if=/dev/zero of="$SHELL_FOLDER/output/rootfs/rootfs.img" bs=1M count=64 2>/dev/null
fi

$SHELL_FOLDER/output/qemu/bin/qemu-system-riscv64 \
    -M quard-star \
    -m 1G \
    -smp 8 \
    -drive if=pflash,bus=0,unit=0,format=raw,file=$SHELL_FOLDER/output/fsbl/fw.bin \
    -drive if=none,format=raw,file=$SHELL_FOLDER/output/rootfs/rootfs.img,id=hd0 \
    -device virtio-blk-device,drive=hd0 \
    -fw_cfg name="opt/qemu_cmdline",string="qemu_vc=1280x720" \
    --serial vc:1280x720 \
    --serial vc:1280x720 \
    --serial vc:1280x720 \
    --monitor vc:1280x720 \
    --parallel none
