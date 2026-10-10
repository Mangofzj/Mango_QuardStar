# Mango_QuardStar

Mango_QuardStar 是基于 RISC-V 架构和 QEMU 的自定义多核异构 SoC 仿真平台，通过构建 Quard Star Board，完成从虚拟硬件平台、启动固件到嵌入式 Linux 系统的软件栈搭建。项目主要包含 QEMU 板级模型、FSBL、OpenSBI、U-Boot、Linux 内核、BusyBox、根文件系统以及相关设备树和构建脚本，实现完整的 RISC-V 嵌入式系统启动流程。

## 项目目录结构

```text
Mango_QuardStar/
├── .gitignore                  # Git 忽略规则
├── CLAUDE.md                   # AI 辅助开发说明
├── build.sh                    # 项目统一构建脚本
├── run.sh                      # QEMU 系统运行脚本
├── qemu-8.0.0/                 # QEMU 8.0.0 源码与 Quard Star 板级模型
├── fsbl/                       # First Stage Boot Loader
│   ├── start.S                 # FSBL 启动代码
│   └── fsbl.lds                # FSBL 链接脚本
├── opensbi-1.2/                # OpenSBI 1.2 源码与板级支持
├── trusted_fw/                 # 可信域测试固件
│   ├── start.S                 # 可信固件启动代码
│   └── trusted_fw.lds          # 可信固件链接脚本
├── u-boot-2023.04/             # U-Boot 2023.04 源码与板级支持
├── linux-6.1.11/               # Linux 6.1.11 内核源码与板级支持
├── busybox-1.33.2/             # BusyBox 1.33.2 源码与系统基础工具
├── dts/                        # Quard Star 设备树与启动配置
│   ├── quard_star.dtsi         # Quard Star 公共设备树
│   ├── quard_star_sbi.dts      # OpenSBI 阶段设备树
│   ├── quard_star_uboot.dts    # U-Boot/Linux 阶段设备树
│   └── quard_star_uboot.cmd    # U-Boot 启动脚本
├── rootfs_overlay/             # 根文件系统自定义配置
└── rootfs_build/               # 根文件系统镜像构建工具
    └── generate_rootfs.sh      # rootfs 镜像生成脚本
