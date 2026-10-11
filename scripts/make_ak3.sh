#!/usr/bin/env bash
# 用 AnyKernel3 把编译好的 Image 打成可直接在 TWRP / 橙狐 / KernelSU 管理器里刷入的 zip
# 用法: bash scripts/make_ak3.sh <Image路径> <输出目录> [zip名称]
set -euo pipefail

log()  { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
warn() { printf '\n\033[1;33m[!] %s\033[0m\n' "$*"; }
die()  { printf '\n\033[1;31m[x] %s\033[0m\n' "$*" >&2; exit 1; }

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE="${1:?需要 Image 路径}"
OUTDIR="${2:?需要输出目录}"
ZIPNAME="${3:-Ace6-GKI-6.6-fengchi-FolkSU.zip}"

[ -f "$IMAGE" ] || die "找不到 Image: $IMAGE"
mkdir -p "$OUTDIR"

WORK="$REPO_ROOT/work/ak3"
rm -rf "$WORK"

# AnyKernel3 骨架: osm0sis 原版优先, 失败回退 cctv18 的 fork (两者 globals 均兼容)
log "拉取 AnyKernel3 骨架"
AK3_OK=0
for R in https://github.com/osm0sis/AnyKernel3.git \
         https://github.com/cctv18/AnyKernel3.git; do
  echo "    尝试 $R"
  if git clone --depth=1 "$R" "$WORK" 2>/dev/null; then
    # 骨架必须自带这些核心文件, 否则脚本里的 globals 不会生效
    if [ -f "$WORK/tools/ak3-core.sh" ] && [ -f "$WORK/tools/magiskboot" ]; then
      AK3_OK=1; echo "    使用 $R"; break
    fi
    warn "骨架缺少 tools/(ak3-core.sh|magiskboot), 换下一个源"
    rm -rf "$WORK"
  fi
done
[ "$AK3_OK" = "1" ] || die "无法获取可用的 AnyKernel3 骨架"

log "写入 Ace 6 专用 anykernel.sh"
cp "$REPO_ROOT/ak3/anykernel.sh" "$WORK/anykernel.sh"
chmod 755 "$WORK/anykernel.sh"

log "放入内核镜像"
cp "$IMAGE" "$WORK/Image"

# 构建信息只作为独立文件放进 zip (绝不能 append 到 anykernel.sh:
# 里面的 "BUILT_AT=2026-10-10 15:21:39 UTC" 不是合法 shell 赋值, 会让安装器报错)
if [ -f "$REPO_ROOT/work/out/build-info.txt" ]; then
  cp "$REPO_ROOT/work/out/build-info.txt" "$WORK/build-info.txt"
fi

cd "$WORK"
rm -rf .git
# 加固: 统一工具权限, 规避 I/O 延迟导致的二进制执行异常
chmod -R 755 tools 2>/dev/null || true

rm -f "$OUTDIR/$ZIPNAME"
node "$REPO_ROOT/scripts/mkzip.js" "$WORK" "$OUTDIR/$ZIPNAME"
log "已生成: $OUTDIR/$ZIPNAME ($(du -h "$OUTDIR/$ZIPNAME" | cut -f1))"
echo "    zip 内容:"
node "$REPO_ROOT/scripts/mkzip.js" --list "$OUTDIR/$ZIPNAME" 2>/dev/null || ls -l "$OUTDIR/$ZIPNAME"
