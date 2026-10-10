#!/usr/bin/env bash
# 用 AnyKernel3 把编译好的 Image 打成可直接在 TWRP / 橙狐 / KernelSU 管理器里刷入的 zip
# 用法: bash scripts/make_ak3.sh <Image路径> <输出目录> [zip名称]
set -euo pipefail

log()  { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
die()  { printf '\n\033[1;31m[x] %s\033[0m\n' "$*" >&2; exit 1; }

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE="${1:?需要 Image 路径}"
OUTDIR="${2:?需要输出目录}"
ZIPNAME="${3:-Ace6-GKI-6.6-fengchi-FolkSU.zip}"

[ -f "$IMAGE" ] || die "找不到 Image: $IMAGE"
mkdir -p "$OUTDIR"

WORK="$REPO_ROOT/work/ak3"
rm -rf "$WORK"
log "拉取 AnyKernel3 骨架"
git clone --depth=1 https://github.com/osm0sis/AnyKernel3.git "$WORK"

log "写入 Ace 6 专用 anykernel.sh"
cp "$REPO_ROOT/ak3/anykernel.sh" "$WORK/anykernel.sh"

log "放入内核镜像"
cp "$IMAGE" "$WORK/Image"

# 记录构建信息, 方便日后追溯
cp "$REPO_ROOT/work/out/build-info.txt" "$WORK/build-info.txt" 2>/dev/null || true
cat "$REPO_ROOT/work/out/build-info.txt" >> "$WORK/anykernel.sh" 2>/dev/null || true

cd "$WORK"
rm -rf .git
rm -f "$OUTDIR/$ZIPNAME"
zip -r9 "$OUTDIR/$ZIPNAME" . -x '.git/*' >/dev/null
log "已生成: $OUTDIR/$ZIPNAME ($(du -h "$OUTDIR/$ZIPNAME" | cut -f1))"
