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

# 打包 pflash 镜像（32MB，FSBL 放在偏移 0）
cd $SHELL_FOLDER/output/fsbl
rm -rf fw.bin
dd of=fw.bin bs=1k count=32k if=/dev/zero 2>/dev/null
dd of=fw.bin bs=1k conv=notrunc seek=0 if=fsbl.bin 2>/dev/null
cd $SHELL_FOLDER

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
cd $SHELL_FOLDER
