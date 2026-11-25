#!/bin/sh
# 给 loongsonla64 平台脚本打 Linux 兼容补丁：
# 原脚本无条件调用 ctypes.windll.kernel32 初始化 Windows 控制台，Linux 下会崩溃。
set -eu

P="${1:-$HOME/.platformio/platforms/loongsonla64/builder/main.py}"
if [ ! -f "$P" ]; then
    echo "找不到平台脚本：$P" >&2
    exit 1
fi

python3 - "$P" <<'PY'
import sys

path = sys.argv[1]
with open(path, encoding="utf-8") as f:
    src = f.read()

old = '\nenable_unicode_console()\n'
new = '\nif sys.platform.startswith("win"):\n    enable_unicode_console()\n'

if new in src:
    print("已打过补丁，跳过")
    sys.exit(0)
if old not in src:
    sys.exit("未找到目标调用，请确认平台包版本后手动修补")

with open(path, "w", encoding="utf-8") as f:
    f.write(src.replace(old, new, 1))
print("已修补", path)
PY
