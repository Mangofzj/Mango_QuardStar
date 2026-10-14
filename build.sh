# 任一环节失败立即停止，避免组件构建失败后继续走完并返回 0（如 BusyBox 失败仍产出 rootfs）
set -e

SHELL_FOLDER=$(cd "$(dirname "$0")";pwd)
CROSS_PREFIX=riscv64-linux-gnu-

# 构建中间产物统一放 build/，最终产物仍放 output/（run.sh 只依赖 output/）
BUILD_DIR="$SHELL_FOLDER/build"
OUTPUT_DIR="$SHELL_FOLDER/output"
mkdir -p "$BUILD_DIR" "$OUTPUT_DIR"

# QEMU（在 build/qemu 下配置编译，源码树保持干净）
mkdir -p "$BUILD_DIR/qemu"
cd "$BUILD_DIR/qemu"
if [ ! -f Makefile ]; then
"$SHELL_FOLDER/qemu-8.0.0/configure" --prefix="$OUTPUT_DIR/qemu" --target-list=riscv64-softmmu --enable-gtk --enable-virtfs --disable-gio
fi
make -j$(nproc)
make install
cd "$SHELL_FOLDER"

# FSBL（First Stage Boot Loader）
if [ ! -d "$SHELL_FOLDER/output/fsbl" ]; then
mkdir -p "$SHELL_FOLDER/output/fsbl"
fi
cd fsbl
${CROSS_PREFIX}gcc -x assembler-with-cpp -fno-pie -c start.S -o $SHELL_FOLDER/output/fsbl/startup.o
${CROSS_PREFIX}gcc -nostartfiles -fno-pie -T./fsbl.lds -Wl,-Map=$SHELL_FOLDER/output/fsbl/fsbl.map \
    -Wl,--gc-sections $SHELL_FOLDER/output/fsbl/startup.o -o $SHELL_FOLDER/output/fsbl/fsbl.elf
${CROSS_PREFIX}objcopy -O binary -S $SHELL_FOLDER/output/fsbl/fsbl.elf $SHELL_FOLDER/output/fsbl/fsbl.bin
${CROSS_PREFIX}objdump --source --demangle --disassemble --reloc --wide \
    $SHELL_FOLDER/output/fsbl/fsbl.elf > $SHELL_FOLDER/output/fsbl/fsbl.lst
cd ..

# OpenSBI（在 build/opensbi 下编译）
if [ ! -d "$OUTPUT_DIR/opensbi" ]; then
mkdir -p "$OUTPUT_DIR/opensbi"
fi
cd opensbi-1.2
make O="$BUILD_DIR/opensbi" CROSS_COMPILE=${CROSS_PREFIX} PLATFORM=quard_star -j$(nproc)
cp "$BUILD_DIR/opensbi/platform/quard_star/firmware/fw_jump.bin" "$OUTPUT_DIR/opensbi/"
cp "$BUILD_DIR/opensbi/platform/quard_star/firmware/fw_jump.elf" "$OUTPUT_DIR/opensbi/"
${CROSS_PREFIX}objdump --source --demangle --disassemble --reloc --wide \
    "$OUTPUT_DIR/opensbi/fw_jump.elf" > "$OUTPUT_DIR/opensbi/fw_jump.lst"
cd "$SHELL_FOLDER"

# Trusted FW（可信域测试固件）
if [ ! -d "$SHELL_FOLDER/output/trusted_fw" ]; then
mkdir -p "$SHELL_FOLDER/output/trusted_fw"
fi
cd trusted_fw
${CROSS_PREFIX}gcc -x assembler-with-cpp -fno-pie -c start.S -o $SHELL_FOLDER/output/trusted_fw/start.o
${CROSS_PREFIX}gcc -nostartfiles -fno-pie -T./trusted_fw.lds -Wl,-Map=$SHELL_FOLDER/output/trusted_fw/trusted_fw.map \
    -Wl,--gc-sections $SHELL_FOLDER/output/trusted_fw/start.o -o $SHELL_FOLDER/output/trusted_fw/trusted_fw.elf
${CROSS_PREFIX}objcopy -O binary -S $SHELL_FOLDER/output/trusted_fw/trusted_fw.elf $SHELL_FOLDER/output/trusted_fw/trusted_fw.bin
${CROSS_PREFIX}objdump --source --demangle --disassemble --reloc --wide \
    $SHELL_FOLDER/output/trusted_fw/trusted_fw.elf > $SHELL_FOLDER/output/trusted_fw/trusted_fw.lst
cd ..

# 设备树（DTS → DTB）
if [ ! -d "$SHELL_FOLDER/output/sbi" ]; then
mkdir -p "$SHELL_FOLDER/output/sbi"
fi
if [ ! -d "$SHELL_FOLDER/output/u-boot" ]; then
mkdir -p "$SHELL_FOLDER/output/u-boot"
fi
cd dts
cpp -nostdinc -I . -undef -x assembler-with-cpp quard_star_sbi.dts | \
    dtc -I dts -O dtb -o $SHELL_FOLDER/output/sbi/quard_star_sbi.dtb
dtc -I dts -O dtb -o $SHELL_FOLDER/output/u-boot/quard_star_uboot.dtb quard_star_uboot.dts
cd ..

# U-Boot（引导加载程序，qemu-quard-star_defconfig 链接地址 0xb0200000；在 build/u-boot 下编译）
cd u-boot-2023.04
make O="$BUILD_DIR/u-boot" CROSS_COMPILE=${CROSS_PREFIX} qemu-quard-star_defconfig
# 用 EXT_DTB 取绝对路径：DEVICE_TREE 会拼上 arch/riscv/dts/ 前缀，层数随构建目录深度变化
make O="$BUILD_DIR/u-boot" CROSS_COMPILE=${CROSS_PREFIX} -j$(nproc) \
    EXT_DTB="$OUTPUT_DIR/u-boot/quard_star_uboot.dtb"
cp "$BUILD_DIR/u-boot/u-boot" "$OUTPUT_DIR/u-boot/u-boot.elf"
cp "$BUILD_DIR/u-boot/u-boot.map" "$OUTPUT_DIR/u-boot/u-boot.map"
cp "$BUILD_DIR/u-boot/u-boot.bin" "$OUTPUT_DIR/u-boot/u-boot.bin"
${CROSS_PREFIX}objdump --source --demangle --disassemble --reloc --wide \
    "$OUTPUT_DIR/u-boot/u-boot.elf" > "$OUTPUT_DIR/u-boot/u-boot.lst"
cd "$SHELL_FOLDER"

# 打包 Parallel NOR Flash 镜像（32MB）
cd $SHELL_FOLDER/output/fsbl
rm -rf fw.bin
dd of=fw.bin bs=1k count=32k if=/dev/zero 2>/dev/null
dd of=fw.bin bs=1k conv=notrunc seek=0 if=fsbl.bin 2>/dev/null
dd of=fw.bin bs=1k conv=notrunc seek=512 if=$SHELL_FOLDER/output/sbi/quard_star_sbi.dtb 2>/dev/null
dd of=fw.bin bs=1k conv=notrunc seek=1K if=$SHELL_FOLDER/output/u-boot/quard_star_uboot.dtb 2>/dev/null
dd of=fw.bin bs=1k conv=notrunc seek=2K if=$SHELL_FOLDER/output/opensbi/fw_jump.bin 2>/dev/null
dd of=fw.bin bs=1k conv=notrunc seek=4K if=$SHELL_FOLDER/output/trusted_fw/trusted_fw.bin 2>/dev/null
dd of=fw.bin bs=1k conv=notrunc seek=8K if=$SHELL_FOLDER/output/u-boot/u-boot.bin 2>/dev/null
cd $SHELL_FOLDER

# Linux 内核（ch11：在 build/linux 下编译生成 Image）
if [ ! -d "$OUTPUT_DIR/linux" ]; then
mkdir -p "$OUTPUT_DIR/linux"
fi
cd linux-6.1.11
make O="$BUILD_DIR/linux" ARCH=riscv CROSS_COMPILE=${CROSS_PREFIX} quard_star_defconfig
make O="$BUILD_DIR/linux" ARCH=riscv CROSS_COMPILE=${CROSS_PREFIX} -j$(nproc)
cp "$BUILD_DIR/linux/arch/riscv/boot/Image" "$OUTPUT_DIR/linux/Image"
cd "$SHELL_FOLDER"

# BusyBox（ch12：静态编译，提供 init 与基础工具集；在 build/busybox 下编译）
if [ ! -d "$OUTPUT_DIR/busybox" ]; then
mkdir -p "$OUTPUT_DIR/busybox"
fi
# BusyBox 的 Makefile 不会自动创建 O= 目录（Kbuild 会），必须先建好
mkdir -p "$BUILD_DIR/busybox"
cd busybox-1.33.2
make O="$BUILD_DIR/busybox" ARCH=riscv CROSS_COMPILE=${CROSS_PREFIX} quard_star_defconfig
make O="$BUILD_DIR/busybox" ARCH=riscv CROSS_COMPILE=${CROSS_PREFIX} -j$(nproc)
# CONFIG_PREFIX 显式指向 output/，不依赖 defconfig 里相对源码树的 ../output/busybox
make O="$BUILD_DIR/busybox" ARCH=riscv CROSS_COMPILE=${CROSS_PREFIX} \
    CONFIG_PREFIX="$OUTPUT_DIR/busybox" install
cd "$SHELL_FOLDER"

# 组装 rootfs.img（ch11 分区 + ch12 BusyBox + ch13 配置脚本与目录）
if [ ! -d "$SHELL_FOLDER/output/rootfs/bootfs" ]; then
mkdir -p "$SHELL_FOLDER/output/rootfs/bootfs"
fi
if [ ! -d "$SHELL_FOLDER/output/rootfs/rootfs" ]; then
mkdir -p "$SHELL_FOLDER/output/rootfs/rootfs"
fi
cp $SHELL_FOLDER/output/linux/Image $SHELL_FOLDER/output/rootfs/bootfs/Image
cp $SHELL_FOLDER/output/u-boot/quard_star_uboot.dtb $SHELL_FOLDER/output/rootfs/bootfs/quard_star.dtb
"$BUILD_DIR/u-boot/tools/mkimage" -A riscv -O linux -T script -C none -a 0 -e 0 -n "Distro Boot Script" -d $SHELL_FOLDER/dts/quard_star_uboot.cmd $SHELL_FOLDER/output/rootfs/bootfs/boot.scr
cp -r $SHELL_FOLDER/output/busybox/* $SHELL_FOLDER/output/rootfs/rootfs/
cp -r $SHELL_FOLDER/rootfs_overlay/* $SHELL_FOLDER/output/rootfs/rootfs/
mkdir -p $SHELL_FOLDER/output/rootfs/rootfs/proc
mkdir -p $SHELL_FOLDER/output/rootfs/rootfs/sys
mkdir -p $SHELL_FOLDER/output/rootfs/rootfs/dev
mkdir -p $SHELL_FOLDER/output/rootfs/rootfs/tmp
chmod +x $SHELL_FOLDER/output/rootfs/rootfs/etc/init.d/rcS
$SHELL_FOLDER/rootfs_build/generate_rootfs.sh $SHELL_FOLDER/output/rootfs/rootfs.img $SHELL_FOLDER/output/rootfs/bootfs $SHELL_FOLDER/output/rootfs/rootfs
