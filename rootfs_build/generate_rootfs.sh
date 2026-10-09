#!/bin/bash
# 生成 rootfs.img：分区 bootfs(vfat) + rootfs(ext4)，无需 root 权限。
# 用 sfdisk 写分区表、mkfs 格式化提取出的分区文件、再回填；分区内容用
# mcopy(vfat) 与 debugfs(ext4) 从暂存目录写入，全程不挂载文件系统。
#
# 用法：generate_rootfs.sh <rootfs.img> <bootfs 暂存目录> <rootfs 暂存目录>
# 分区布局（1GB）：
#   p1 bootfs: start=2048,  size=196608 (96MB),  type=c (vfat)
#   p2 rootfs: start=198656, size=1898496(927MB), type=83 (ext4)

IMG=$1
BOOTFS_STAGE=$2
ROOTFS_STAGE=$3

if [ -z "$IMG" ] || [ -z "$BOOTFS_STAGE" ] || [ -z "$ROOTFS_STAGE" ]; then
    echo "用法: $0 <rootfs.img> <bootfs 暂存目录> <rootfs 暂存目录>"
    exit 1
fi

BOOT_IMG=/tmp/qs_boot.img
ROOT_IMG=/tmp/qs_root.img
DBG_CMDS=/tmp/qs_dbg.cmds
BOOT_OFFSET=$((2048 * 512))
ROOT_OFFSET=$((198656 * 512))

# 1. 创建 1GB 空镜像并写 MBR 分区表（sfdisk 直接作用于文件，无需 loop 设备）
dd if=/dev/zero of="$IMG" bs=1M count=1024 status=none
sfdisk "$IMG" >/dev/null <<EOF
label: dos
label-id: 0x32a47f23
unit: sectors
start=2048, size=196608, type=c
start=198656, size=1898496, type=83
EOF

# 2. 提取 bootfs 分区 → 格式化 vfat → 回填
dd if="$IMG" of="$BOOT_IMG" bs=512 skip=2048 count=196608 status=none
mkfs.vfat "$BOOT_IMG" >/dev/null 2>&1
dd if="$BOOT_IMG" of="$IMG" bs=512 seek=2048 count=196608 conv=notrunc status=none

# 3. 提取 rootfs 分区 → 格式化 ext4 → 回填
dd if="$IMG" of="$ROOT_IMG" bs=512 skip=198656 count=1898496 status=none
mkfs.ext4 -F "$ROOT_IMG" >/dev/null 2>&1
dd if="$ROOT_IMG" of="$IMG" bs=512 seek=198656 count=1898496 conv=notrunc status=none

# 4. 填充 bootfs（vfat p1）：mcopy 逐文件写入，偏移用字节（@@）
for f in "$BOOTFS_STAGE"/*; do
    [ -e "$f" ] || continue
    mcopy -i "$IMG"@@$BOOT_OFFSET -o "$f" ::
done

# 5. 填充 rootfs（ext4 p2）：生成 debugfs 命令文件后写入提取出的分区文件
#    注意 debugfs 1.45 的 write 不认绝对路径，须先 cd 到父目录再写相对文件名
gen_debugfs_cmds() {
    local src="$1" out="$2"
    : > "$out"
    find "$src" -type d | sort | while IFS= read -r d; do
        local rel="${d#$src}"
        [ -n "$rel" ] && echo "mkdir $rel"
    done >> "$out"
    find "$src" ! -type d | sort | while IFS= read -r f; do
        local rel="${f#$src}"
        if [ -L "$f" ]; then
            # debugfs 对含斜杠的相对目标按当前目录解析，须先回到根再建链接
            echo "cd /"
            echo "symlink $rel $(readlink "$f")"
        else
            local parent="${rel%/*}"
            local base="${rel##*/}"
            [ "$parent" = "$rel" ] && parent=""
            echo "cd ${parent:-/}"
            echo "write $f $base"
        fi
    done >> "$out"
}

gen_debugfs_cmds "$ROOTFS_STAGE" "$DBG_CMDS"
debugfs -w -f "$DBG_CMDS" "$ROOT_IMG" >/dev/null 2>&1
dd if="$ROOT_IMG" of="$IMG" bs=512 seek=198656 count=1898496 conv=notrunc status=none

rm -f "$BOOT_IMG" "$ROOT_IMG" "$DBG_CMDS"
sync
echo "rootfs.img 完成：p1(bootfs vfat 96MB) + p2(rootfs ext4 927MB)"
