# U-Boot Distro Boot 脚本：从 virtio 块设备第 1 分区(bootfs)加载内核与设备树，booti 引导。
load virtio 0:1 ${fdt_addr_r} /quard_star.dtb
load virtio 0:1 ${kernel_addr_r} /Image
booti ${kernel_addr_r} - ${fdt_addr_r}
