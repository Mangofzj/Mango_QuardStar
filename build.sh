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

# ZSBL（Zero Stage Boot Loader）
if [ ! -d "$SHELL_FOLDER/output/zsbl" ]; then
mkdir -p "$SHELL_FOLDER/output/zsbl"
fi
cd zsbl
${CROSS_PREFIX}gcc -x assembler-with-cpp -fno-pie -c startup.S -o $SHELL_FOLDER/output/zsbl/startup.o
${CROSS_PREFIX}gcc -nostartfiles -fno-pie -T./boot.lds -Wl,-Map=$SHELL_FOLDER/output/zsbl/zsbl.map \
    -Wl,--gc-sections $SHELL_FOLDER/output/zsbl/startup.o -o $SHELL_FOLDER/output/zsbl/zsbl.elf
${CROSS_PREFIX}objcopy -O binary -S $SHELL_FOLDER/output/zsbl/zsbl.elf $SHELL_FOLDER/output/zsbl/zsbl.bin
${CROSS_PREFIX}objdump --source --demangle --disassemble --reloc --wide \
    $SHELL_FOLDER/output/zsbl/zsbl.elf > $SHELL_FOLDER/output/zsbl/zsbl.lst

# 打包 pflash 镜像（32MB，ZSBL 放在偏移 0）
cd $SHELL_FOLDER/output/zsbl
rm -rf fw.bin
dd of=fw.bin bs=1k count=32k if=/dev/zero 2>/dev/null
dd of=fw.bin bs=1k conv=notrunc seek=0 if=zsbl.bin 2>/dev/null
cd $SHELL_FOLDER
