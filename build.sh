SHELL_FOLDER=$(cd "$(dirname "$0")";pwd)
CROSS_PREFIX=riscv64-linux-gnu-

# QEMU
cd qemu-8.0.0
if [ ! -d "$SHELL_FOLDER/output/qemu" ]; then
./configure --prefix=$SHELL_FOLDER/output/qemu --target-list=riscv64-softmmu --enable-gtk --enable-virtfs --disable-gio
fi
make -j$(nproc)
make install
cd ..

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

# OpenSBI
if [ ! -d "$SHELL_FOLDER/output/opensbi" ]; then
mkdir -p "$SHELL_FOLDER/output/opensbi"
fi
cd opensbi-1.2
make CROSS_COMPILE=${CROSS_PREFIX} PLATFORM=quard_star -j$(nproc)
cp build/platform/quard_star/firmware/fw_jump.bin $SHELL_FOLDER/output/opensbi/
cp build/platform/quard_star/firmware/fw_jump.elf $SHELL_FOLDER/output/opensbi/
${CROSS_PREFIX}objdump --source --demangle --disassemble --reloc --wide \
    $SHELL_FOLDER/output/opensbi/fw_jump.elf > $SHELL_FOLDER/output/opensbi/fw_jump.lst
cd ..

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
if [ ! -d "$SHELL_FOLDER/output/uboot" ]; then
mkdir -p "$SHELL_FOLDER/output/uboot"
fi
cd dts
cpp -nostdinc -I . -undef -x assembler-with-cpp quard_star_sbi.dts | \
    dtc -I dts -O dtb -o $SHELL_FOLDER/output/sbi/quard_star_sbi.dtb
dtc -I dts -O dtb -o $SHELL_FOLDER/output/uboot/quard_star_uboot.dtb quard_star_uboot.dts
cd ..

# U-Boot（引导加载程序，qemu-quard-star_defconfig 链接地址 0xb0200000）
cd u-boot-2023.04
make CROSS_COMPILE=${CROSS_PREFIX} qemu-quard-star_defconfig
make CROSS_COMPILE=${CROSS_PREFIX} -j$(nproc) DEVICE_TREE=../../../../output/uboot/quard_star_uboot
cp u-boot $SHELL_FOLDER/output/uboot/u-boot.elf
cp u-boot.map $SHELL_FOLDER/output/uboot/u-boot.map
cp u-boot.bin $SHELL_FOLDER/output/uboot/u-boot.bin
${CROSS_PREFIX}objdump --source --demangle --disassemble --reloc --wide \
    $SHELL_FOLDER/output/uboot/u-boot.elf > $SHELL_FOLDER/output/uboot/u-boot.lst
cd ..

# 打包 Parallel NOR Flash 镜像（32MB）
cd $SHELL_FOLDER/output/fsbl
rm -rf fw.bin
dd of=fw.bin bs=1k count=32k if=/dev/zero 2>/dev/null
dd of=fw.bin bs=1k conv=notrunc seek=0 if=fsbl.bin 2>/dev/null
dd of=fw.bin bs=1k conv=notrunc seek=512 if=$SHELL_FOLDER/output/sbi/quard_star_sbi.dtb 2>/dev/null
dd of=fw.bin bs=1k conv=notrunc seek=1K if=$SHELL_FOLDER/output/uboot/quard_star_uboot.dtb 2>/dev/null
dd of=fw.bin bs=1k conv=notrunc seek=2K if=$SHELL_FOLDER/output/opensbi/fw_jump.bin 2>/dev/null
dd of=fw.bin bs=1k conv=notrunc seek=4K if=$SHELL_FOLDER/output/trusted_fw/trusted_fw.bin 2>/dev/null
dd of=fw.bin bs=1k conv=notrunc seek=8K if=$SHELL_FOLDER/output/uboot/u-boot.bin 2>/dev/null
cd $SHELL_FOLDER

# Linux 内核（ch11：编译生成 Image）
if [ ! -d "$SHELL_FOLDER/output/linux_kernel" ]; then
mkdir -p "$SHELL_FOLDER/output/linux_kernel"
fi
cd linux-6.1.11
make ARCH=riscv CROSS_COMPILE=${CROSS_PREFIX} quard_star_defconfig
make ARCH=riscv CROSS_COMPILE=${CROSS_PREFIX} -j$(nproc)
cp arch/riscv/boot/Image $SHELL_FOLDER/output/linux_kernel/Image
cd $SHELL_FOLDER

# BusyBox（ch12：静态编译，提供 init 与基础工具集）
if [ ! -d "$SHELL_FOLDER/output/busybox" ]; then
mkdir -p "$SHELL_FOLDER/output/busybox"
fi
cd busybox-1.33.2
make ARCH=riscv CROSS_COMPILE=${CROSS_PREFIX} quard_star_defconfig
make ARCH=riscv CROSS_COMPILE=${CROSS_PREFIX} -j$(nproc)
make ARCH=riscv CROSS_COMPILE=${CROSS_PREFIX} install
cd $SHELL_FOLDER

# 组装 rootfs.img（ch11 分区 + ch12 填充 BusyBox，无 root）
if [ ! -d "$SHELL_FOLDER/output/rootfs/bootfs" ]; then
mkdir -p "$SHELL_FOLDER/output/rootfs/bootfs"
fi
if [ ! -d "$SHELL_FOLDER/output/rootfs/rootfs" ]; then
mkdir -p "$SHELL_FOLDER/output/rootfs/rootfs"
fi
cp $SHELL_FOLDER/output/linux_kernel/Image $SHELL_FOLDER/output/rootfs/bootfs/Image
cp $SHELL_FOLDER/output/uboot/quard_star_uboot.dtb $SHELL_FOLDER/output/rootfs/bootfs/quard_star.dtb
$SHELL_FOLDER/u-boot-2023.04/tools/mkimage -A riscv -O linux -T script -C none -a 0 -e 0 -n "Distro Boot Script" -d $SHELL_FOLDER/dts/quard_star_uboot.cmd $SHELL_FOLDER/output/rootfs/bootfs/boot.scr
cp -r $SHELL_FOLDER/output/busybox/* $SHELL_FOLDER/output/rootfs/rootfs/
$SHELL_FOLDER/build_rootfs/generate_rootfs.sh $SHELL_FOLDER/output/rootfs/rootfs.img $SHELL_FOLDER/output/rootfs/bootfs $SHELL_FOLDER/output/rootfs/rootfs
