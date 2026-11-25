# 在 loongarch64 Linux 上复刻 LOONGIDE 的 la64 开发环境

本教程记录如何把 `ide.loongfans.cn` 上 LOONGIDE 的 **la64 编译能力**搬到
loongarch64 Linux 本机，全程**不需要 root**、不依赖 Windows，也不使用官方 Windows 安装包。
最终可用 PlatformIO 原生编译龙芯 la64（如 2K300/2K0300）固件。

## 背景与适用范围

LOONGIDE 本质是 **VSCode/VSCodium + PlatformIO + OpenOCD + GCC/GDB** 的打包方案，
另带两个 PlatformIO 平台包：`loongsonla32`、`loongsonla64`。官网首页宣称支持
龙架构 Linux，但实际分发和文档有明显限制：

- 下载页只提供 Windows 与 Linux x86-64 二进制，文档全部是 Windows 环境指南；
- 平台脚本 `builder/main.py` **无条件调用 `ctypes.windll.kernel32`**，在 Linux 上直接
  `AttributeError`；
- 官方 Gitea 上的工具链/框架包 `package.json` 只声明 `windows_amd64` / `windows_arm64`，
  PlatformIO 在 Linux 会拒绝安装；
- 示例工程依赖的自定义包不在 PlatformIO 官方 registry 上。

本教程绕过以上限制，用系统自带的 GCC/binutils 组成“本地包”，让同一个 PlatformIO
平台在 loongarch64 Linux 上正常工作。

适用环境：

- loongarch64 Linux（示例为 AOSC OS，其他发行版路径按实际调整）；
- Python 3.10+，可用 pip；
- 系统已有 `loongarch64-linux-gnu-gcc`（或原生 `gcc`）+ binutils（`as`/`ar`/`objcopy` 等）；
- 不需要 JTAG 调试器即可完成编译验证。

## 已知坑与对策

| 现象 | 原因 | 对策 |
|---|---|---|
| `AttributeError: module 'ctypes' has no attribute 'windll'` | 平台脚本无条件初始化 Windows 控制台 | 用 `scripts/patch-platform.sh` 加 `sys.platform.startswith("win")` 守卫 |
| PlatformIO 拒绝安装 `toolchain-loongarch64` | 官方包只声明 Windows 平台 | 用本地包，`package.json` 写 `"system": ["linux_loongarch64"]` |
| 找不到 `loongarch64-linux-gnu-*` | 发行版未装交叉工具链 | la64 与目标架构相同，可直接把系统 binutils 做符号链接 |

## 步骤 1：安装 PlatformIO Core（用户级 venv）

```sh
python3 -m venv ~/platformio-venv
~/platformio-venv/bin/python -m pip install platformio
~/platformio-venv/bin/pio --version
```

若默认 PyPI 连接不稳定，可加镜像，例如
`-i https://pypi.tuna.tsinghua.edu.cn/simple`。

## 步骤 2：取得并修补 la64 平台包

平台包源码在 `https://git.loongfans.cn/LoongIDE/loongide`（公开仓库），下载 main 分支
ZIP 后解出 `loongsonla64` 目录：

```sh
export WORK=~/work/loongide-la64
mkdir -p "$WORK"
curl -L -o "$WORK/loongide.zip" \
  https://git.loongfans.cn/LoongIDE/loongide/archive/main.zip
mkdir -p ~/.platformio/platforms
python3 - <<'PY'
import os, zipfile
z = zipfile.ZipFile(os.path.expanduser("~/work/loongide-la64/loongide.zip"))
prefix, out = "loongide/loongsonla64/", os.path.expanduser("~/.platformio/platforms/loongsonla64")
for i in z.infolist():
    if not i.filename.startswith(prefix):
        continue
    rel = i.filename[len(prefix):]
    if not rel:
        continue
    target = os.path.join(out, rel)
    if i.is_dir():
        os.makedirs(target, exist_ok=True)
    else:
        os.makedirs(os.path.dirname(target), exist_ok=True)
        with z.open(i) as src, open(target, "wb") as dst:
            dst.write(src.read())
PY
sh scripts/patch-platform.sh
```

`scripts/patch-platform.sh` 会修改
`~/.platformio/platforms/loongsonla64/builder/main.py`，把无条件调用改成仅 Windows 执行。
可用 `sh scripts/patch-platform.sh /path/to/main.py` 指定其他位置。

## 步骤 3：生成 Linux 本地包

```sh
sh scripts/make-local-packages.sh
```

脚本会在 `~/.platformio/packages/` 下创建：

- `framework-allinone/` —— 只有元数据的本地框架包；
- `toolchain-loongarch64/` —— `bin/` 里是把系统 GCC/binutils 映射成
  `loongarch64-linux-gnu-*` 名称的符号链接。

脚本会优先找带前缀的工具，找不到则回退到系统同名工具；缺失项会在终端列出。

## 步骤 4：编译最小工程

```sh
cd examples/minimal
sed -i "s|<HOME>|$(echo $HOME)|g" platformio.ini
~/platformio-venv/bin/pio run
```

成功时输出 `[SUCCESS]`，并生成：

```
.pio/build/ls2k300/firmware.elf
.pio/build/ls2k300/firmware.bin
```

用 `file .pio/build/ls2k300/firmware.elf` 应看到 `ELF 64-bit ... LoongArch`。

## 步骤 5：编译官方 RT-Thread 示例（可选）

官方示例在 ZIP 的 `loongide/loongsonla64/examples/platformio-ls2k0300/`，内含完整
RT-Thread SDK。解出后按本教程步骤 2/3 准备好平台与本地包，再把 `platformio.ini` 里的
`platform_packages` 段替换为：

```ini
platform_packages =
    toolchain-loongarch64 @ file://<HOME>/.platformio/packages/toolchain-loongarch64
    framework-allinone @ file://<HOME>/.platformio/packages/framework-allinone
```

示例原文件还引用 git 版 `toolchain-loongarch32`、`tool-openocd`，这些在 Linux 上不可用，
应删除。`extra_scripts` 里的 `check_env.py` 只挂到 `upload`，不影响 `pio run`。

已验证该示例可编译通过（GCC 16.2.0 / binutils 2.47，PlatformIO Core 6.2.0）：

```
RAM:   [=         ]  12.5% (used 57432 bytes from 458752 bytes)
Flash: [=         ]   7.0% (used 73896 bytes from 1048576 bytes)
========================= [SUCCESS] Took 3.92 seconds =========================
```

链接阶段可能出现 `LOAD segment with RWX permissions` 警告，不影响产物生成。

## 未覆盖的范围

- **la32 开发**：需要 `loongarch32-linux-gnusf-gcc`，本机通常没有；旧版 LoongIDE 的 deb
  自带 `loongarch32-newlib-elf-*`，但那是 Windows/旧 glibc 生态，不能直接使用。
- **烧录与调试**：平台脚本的 `upload` 命令是 Windows 反斜杠路径，需自行改写；
  OpenOCD 可从发行版源安装（如 `openocd 0.12.0`），再按调试器型号写 cfg。
- **图形前端**：本教程用命令行 `pio`。需要 IDE 时可自行安装 VSCodium + PlatformIO 插件。

## 脱敏说明

本教程与脚本中的路径全部使用 `~` / `<HOME>` 占位符，不含任何主机名、IP、账号、
令牌或私有网络信息。引用链接均为公开仓库地址。
