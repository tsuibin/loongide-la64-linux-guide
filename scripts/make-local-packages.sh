#!/bin/sh
# 用系统 GCC/binutils 构造 PlatformIO 本地包，绕开官方包的 Windows-only 声明。
set -eu

PACKAGES="${PLATFORMIO_CORE_DIR:-$HOME/.platformio}/packages"
mkdir -p "$PACKAGES/framework-allinone" "$PACKAGES/toolchain-loongarch64/bin"

cat > "$PACKAGES/framework-allinone/package.json" <<'EOF'
{
  "name": "framework-allinone",
  "version": "1.0.0",
  "description": "Local metadata package for LoongArch allinone framework",
  "system": ["linux_loongarch64"]
}
EOF

cat > "$PACKAGES/toolchain-loongarch64/package.json" <<'EOF'
{
  "name": "toolchain-loongarch64",
  "version": "1.0.0",
  "description": "Local loongarch64 toolchain mapped to system GCC/binutils",
  "system": ["linux_loongarch64"]
}
EOF

# 优先用带交叉前缀的命令，找不到则回退到系统原生同名命令。
resolve() {
    prefixed="$1"
    fallback="$2"
    if command -v "$prefixed" >/dev/null 2>&1; then
        command -v "$prefixed"
    elif command -v "$fallback" >/dev/null 2>&1; then
        command -v "$fallback"
    else
        echo "MISSING"
    fi
}

BIN="$PACKAGES/toolchain-loongarch64/bin"
for pair in \
    "gcc:gcc" \
    "g++:g++" \
    "as:as" \
    "ar:ar" \
    "gcc-ar:gcc-ar" \
    "ranlib:ranlib" \
    "gcc-ranlib:gcc-ranlib" \
    "nm:nm" \
    "gcc-nm:gcc-nm" \
    "objcopy:objcopy" \
    "objdump:objdump" \
    "readelf:readelf" \
    "size:size" \
    "strip:strip" \
    "strings:strings" \
    "ld:ld" \
    "gdb:gdb"
do
    tool="${pair%%:*}"
    fallback="${pair#*:}"
    target="$(resolve "loongarch64-linux-gnu-$tool" "$fallback")"
    if [ "$target" = "MISSING" ]; then
        echo "警告：缺少工具 $tool（已跳过）" >&2
    else
        ln -sf "$target" "$BIN/loongarch64-linux-gnu-$tool"
    fi
done

echo "本地包已生成：$PACKAGES"
echo "工具链链接："
ls -1 "$BIN"
