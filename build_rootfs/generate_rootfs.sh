#!/bin/bash
# 生成 rootfs.img：分区 bootfs(vfat) + rootfs(ext4)，无需 root 权限。
# 用 sfdisk 写分区表、mkfs 格式化提取出的分区文件、再回填，全程作用于普通文件。
#
# 用法：generate_rootfs.sh <rootfs.img 路径>
# 分区布局（1GB）：
#   p1 bootfs: start=2048,  size=196608 (96MB),  type=c (vfat)
#   p2 rootfs: start=198656, size=1898496(927MB), type=83 (ext4)

IMG=$1

if [ -z "$IMG" ]; then
    echo "用法: $0 <rootfs.img 路径>"
    exit 1
fi

BOOT_IMG=/tmp/qs_boot.img
ROOT_IMG=/tmp/qs_root.img

# 1. 创建 1GB 空镜像
dd if=/dev/zero of="$IMG" bs=1M count=1024 status=none

# 2. 写 MBR 分区表（sfdisk 直接作用于文件，无需 loop 设备）
sfdisk "$IMG" >/dev/null <<EOF
label: dos
label-id: 0x32a47f23
unit: sectors
start=2048, size=196608, type=c
start=198656, size=1898496, type=83
EOF

# 3. 提取 bootfs 分区 → 格式化 vfat → 回填
dd if="$IMG" of="$BOOT_IMG" bs=512 skip=2048 count=196608 status=none
mkfs.vfat "$BOOT_IMG" >/dev/null 2>&1
dd if="$BOOT_IMG" of="$IMG" bs=512 seek=2048 count=196608 conv=notrunc status=none

# 4. 提取 rootfs 分区 → 格式化 ext4 → 回填
dd if="$IMG" of="$ROOT_IMG" bs=512 skip=198656 count=1898496 status=none
mkfs.ext4 -F "$ROOT_IMG" >/dev/null 2>&1
dd if="$ROOT_IMG" of="$IMG" bs=512 seek=198656 count=1898496 conv=notrunc status=none

rm -f "$BOOT_IMG" "$ROOT_IMG"
sync
echo "rootfs.img 分区完成：p1(bootfs vfat 96MB) + p2(rootfs ext4 927MB)"
