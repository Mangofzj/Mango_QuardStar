# 项目概述

Quard Star — 基于 QEMU 8.0.0 的自定义 RISC-V 多核异构板卡仿真平台。用于学习和验证 RISC-V 架构、SoC 外设驱动及嵌入式 Linux 系统。

## 技术栈

- **虚拟化**: QEMU 8.0.0（C 语言，meson 构建系统）
- **目标架构**: RISC-V 64-bit（riscv64-softmmu）
- **构建系统**: meson + ninja，外层由 `build.sh` 封装 configure/make 流程
- **关键依赖**: GTK（图形界面）、VirtFS（宿主机文件共享）

## 关键约定

- QEMU 采用 out-of-tree 构建，编译产物在 `qemu-8.0.0/build/`，禁止提交
- 所有对 QEMU 源码的定制修改集中在 `hw/riscv/quard_star.*` 及相关文件中
- 构建输出目录 `output/` 为安装产物，禁止提交
- 板卡初始化代码遵循 QEMU machine model 规范（TypeInfo + MachineClass）

## 目录结构

```
.
├── build.sh                 # 一键配置、编译、安装 QEMU
├── output/qemu/             # 编译安装输出（bin/include/libexec/share）
└── qemu-8.0.0/              # QEMU 8.0.0 源码（含定制修改）
    ├── hw/riscv/            # RISC-V 板卡模型
    │   └── quard_star.c     # Quard Star 板卡定义（自定义）
    ├── build/               # meson 编译中间产物（已忽略）
    └── ...                  # 其余 QEMU 原生源码
```

## 常用命令

### 开发

```bash
# 完整构建（配置 + 编译 + 安装）
./build.sh

# 仅编译（跳过 configure）
cd qemu-8.0.0 && make -j$(nproc)

# 运行 QEMU
./output/qemu/bin/qemu-system-riscv64 -M quard_star [其他参数...]
```

### 审查

```bash
# 查看当前分支状态
git status

# 查看提交历史
git log --oneline --graph

# 查看与 main 的差异
git diff main..HEAD
```

### 测试

```bash
# 快速检查 QEMU 是否能启动
./output/qemu/bin/qemu-system-riscv64 -M quard_star -nographic
```

## 编码规范

### 注释风格
- 注释参考 Linux 内核风格：解释某一句时，与代码同行，代码和 `//` 间留两个空格，`//` 和注释内容间留一个空格；解释某一段时，放代码上方，`/*` 与当前缩进层级对齐，`/*` 和注释内容间留一个空格。
- 文件/函数头采用 Doxygen 风格：文件头描述职责，函数头描述功能，按需使用 @param/@return/@note 分段说明。
- 语句在准确的前提下保持精简：文件/函数头能一行说清不写多行；注释只补充无法自解释的关键信息。

### 命名风格

- 函数名: `snake_case`，符合 QEMU code style（如 `quard_star_machine_init`）
- 宏 / 常量: `UPPER_CASE`（如 `QUARD_STAR_BASE_ADDR`）
- 类型名: `PascalCase`（如 `QuardStarMachineState`）
- TypeInfo 变量名: `xxx_info` 结尾（如 `quard_star_machine_info`）

## Git Flow

| 分支类型 | 生命周期 | 核心职责 | 命名规范 |
|----------|----------|----------|----------|
| `main`   | 永久     | 始终可构建，阶段性打 tag | `main` |
| `feat`   | 临时     | 从 main 创建，完成后合并回 main 并删除 | `feat/功能名` |

## 参考教程

[Quard Star 教程](https://quard-star-tutorial.readthedocs.io/zh-cn/latest/index.html) — 本项目全程跟随此教程逐步构建。

- **硬件架构**：多核 RISC-V SoC 仿真板，包含 CPU 集群、丰富外设（UART、I2C、SPI、网卡、USB、LCD 等）。

- **软件启动链**：Mask ROM → OpenSBI → U-Boot → Linux Kernel → rootfs。

- **章节概览**：

| 阶段 | 章节 | 内容 |
|------|------|------|
| 板卡基础 | ch1-ch4 | 搭建 QEMU 环境、添加 Quard-Star 板、中断控制器、串口、pflash、测试固件 |
| 启动引导 | ch5-ch9 | OpenSBI、设备树、U-Boot 移植、内存重规划 |
| 内核与文件系统 | ch10-ch15 | virtio/fw_cfg、Linux Kernel 启动、busybox、根文件系统、动态链接、多用户 |
| 外设与应用 | ch16-ch25 | Framebuffer、bash/Qt/网络/SSHD、FreeRTOS 移植等 |
| 扩展 | ext1-ext6 | kgdb 调试、gcc profile、gdbstub、CAN 总线、ifplugd 等 |
