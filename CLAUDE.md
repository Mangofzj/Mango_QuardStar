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
