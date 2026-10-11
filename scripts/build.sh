#!/usr/bin/env bash
# =============================================================================
# 一加 Ace 6 (PLQ110 / ossi / SM8750 "sun") GKI 6.6 内核编译脚本
#
#   * 源码基线 : OnePlus 官方开源 android_kernel_common_oneplus_sm8750
#                分支 oneplus/sm8750_b_16.0.0_ace_6  (6.6.118)
#                该分支 gki_defconfig 自带 CONFIG_SLIM_SCHED=y +
#                CONFIG_SCHED_CLASS_EXT=y, 与风驰补丁的基线逐字吻合
#   * 风驰内核 : patches/fengchi.patch
#                (OPlus HMBIRD 调度类: 以 hmbird 取代 AOSP sched_ext,
#                 SCHED_EXT -> SCHED_HMBIRD, CONFIG_SCHED_CLASS_EXT ->
#                 CONFIG_HMBIRD_SCHED, 新增 kernel/sched/hmbird/)
#   * Root     : FolkSU (KernelSU fork, KERNEL_SU_UAPI_VERSION = 5)
#                并把指定 APK 的签名设为内核侧受信任管理器
#
# 用法:  bash scripts/build.sh        (仓库根目录执行)
# 所有参数都可用环境变量覆盖, 见下面 CONFIG 段
# =============================================================================
set -euo pipefail

log()  { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
warn() { printf '\n\033[1;33m[!] %s\033[0m\n' "$*"; }
die()  { printf '\n\033[1;31m[x] %s\033[0m\n' "$*" >&2; exit 1; }

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKDIR="${WORKDIR:-$REPO_ROOT/work}"
mkdir -p "$WORKDIR"

# ------------------------------ CONFIG --------------------------------------
KERNEL_REPO="${KERNEL_REPO:-https://github.com/OnePlusOSS/android_kernel_common_oneplus_sm8750.git}"
KERNEL_BRANCH="${KERNEL_BRANCH:-oneplus/sm8750_b_16.0.0_ace_6}"
KERNEL_DIR="${KERNEL_DIR:-common}"

FOLKSU_REPO="${FOLKSU_REPO:-https://github.com/LyraVoid/FolkSU.git}"
FOLKSU_TAG="${FOLKSU_TAG:-v0.1.0-beta2}"   # == FolkSU_v0.1.0-beta2_32783-release.apk

APPLY_FENGCHI="${APPLY_FENGCHI:-1}"
APPLY_SUSFS="${APPLY_SUSFS:-0}"
# APPLY_KSU=0: 内核里【不】集成 KernelSU。
# 一加 Ace 6 这台机器的 root 是 init_boot ramdisk 里的 kernelsu.ko (LKM 模式,
# ksu_config 里 bundled=1, 由 wrapper init / ksuinit 在开机时 insmod)。
# 内核自带 KSU 时, ksuinit 会走到 "Cannot load kernelsu.ko" 分支 -> init 卡住 -> 卡第一屏。
APPLY_KSU="${APPLY_KSU:-1}"
# ENABLE_BTF=1: 生成 BTF (/sys/kernel/btf/vmlinux)。
# 第三方 sched_ext (scx_rusty / scx_lavd 等 BPF 调度器) 走 CO-RE, 必须要有 BTF;
# 设备出厂内核就是 DEBUG_INFO_BTF=y + DEBUG_INFO_BTF_MODULES=y + MODULE_ALLOW_BTF_MISMATCH=y。
# 需要 CI 里装 pahole (apt 包 dwarves)。
ENABLE_BTF="${ENABLE_BTF:-0}"

# FolkSU 管理器证书的 (长度, SHA-256), 用 scripts/apk_sign.py 从 APK 提取
KSU_EXPECTED_SIZE="${KSU_EXPECTED_SIZE:-0x2cc}"
KSU_EXPECTED_HASH="${KSU_EXPECTED_HASH:-2d89b50aaf1db013c2b6738f973f48b62ea21a3a8d7216bfec3521065d448458}"

# 出厂 vendor_dlkm 的 vermagic 为 6.6.118-android15-8-o-4k, 这里逐字对齐
LOCALVERSION_SUFFIX="${LOCALVERSION_SUFFIX:--android15-8-o-4k}"

CLANG_VER="${CLANG_VER:-18}"
JOBS="${JOBS:-$(nproc --all)}"
BUILD_TARGET="${BUILD_TARGET:-Image}"
INSTALL_DEPS="${INSTALL_DEPS:-0}"

export KBUILD_BUILD_USER="${KBUILD_BUILD_USER:-ace6}"
export KBUILD_BUILD_HOST="${KBUILD_BUILD_HOST:-gki-builder}"
export KBUILD_BUILD_TIMESTAMP="${KBUILD_BUILD_TIMESTAMP:-$(date -u '+%Y-%m-%d %H:%M:%S UTC')}"

# --------------------------- 依赖安装 (可选) ---------------------------------
if [ "$INSTALL_DEPS" = "1" ]; then
  log "安装编译依赖"
  SUDO=""; [ "$(id -u)" -eq 0 ] || SUDO="sudo"
  $SUDO apt-get update -qq
  $SUDO apt-get install -y --no-install-recommends \
    bc bison flex libelf-dev libssl-dev cpio zip unzip rsync kmod ccache \
    gcc-aarch64-linux-gnu binutils-aarch64-linux-gnu python3 git wget curl xz-utils
  if ! command -v "clang-$CLANG_VER" >/dev/null 2>&1; then
    wget -q https://apt.llvm.org/llvm.sh -O /tmp/llvm.sh
    chmod +x /tmp/llvm.sh
    $SUDO /tmp/llvm.sh "$CLANG_VER" all
  fi
fi

for t in "clang-$CLANG_VER" "ld.lld-$CLANG_VER" aarch64-linux-gnu-ld make bc bison flex git; do
  command -v "$t" >/dev/null 2>&1 || die "缺少工具: $t  (设 INSTALL_DEPS=1 或手动安装)"
done

# --------------------------- 1. 官方 Ace 6 源码 ------------------------------
cd "$WORKDIR"
if [ ! -d "$KERNEL_DIR/.git" ]; then
  log "克隆 OnePlus 官方 Ace 6 内核源码"
  echo "    仓库: $KERNEL_REPO"
  echo "    分支: $KERNEL_BRANCH"
  git clone --depth=1 --branch "$KERNEL_BRANCH" "$KERNEL_REPO" "$KERNEL_DIR"
else
  log "复用已存在的 $KERNEL_DIR"
fi
cd "$KERNEL_DIR"

BASE_VERSION="$(make kernelversion 2>/dev/null || echo unknown)"
SRC_HEAD="$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
log "基线: Linux $BASE_VERSION  提交 $SRC_HEAD"
git log -1 --pretty='    %s' 2>/dev/null || true

# --------------------------- 2. 风驰内核补丁 ---------------------------------
if [ "$APPLY_FENGCHI" = "1" ]; then
  log "移植风驰内核 (HMBIRD 调度类)"
  # fengchi-ace6.patch = 上游 fengchi.patch 在官方 ace_6 分支上重基后的版本,
  # 19 处基线漂移已逐条解决, 并验证 git apply 0 reject
  PATCH_FILE="$REPO_ROOT/patches/fengchi-ace6.patch"
  [ -f "$PATCH_FILE" ] || PATCH_FILE="$REPO_ROOT/patches/fengchi.patch"
  [ -f "$PATCH_FILE" ] || die "找不到风驰补丁"
  echo "    补丁: $(basename "$PATCH_FILE")"

  # 风驰以 hmbird 取代 AOSP sched_ext, 基线必须是带 SLIM_SCHED/SCHED_CLASS_EXT 的树
  grep -q '^CONFIG_SCHED_CLASS_EXT=y' arch/arm64/configs/gki_defconfig \
    || warn "基线 gki_defconfig 没有 CONFIG_SCHED_CLASS_EXT=y, 补丁可能不匹配"

  APPLIED=0
  if git apply -p1 --whitespace=nowarn "$PATCH_FILE" 2>/dev/null; then
    echo "    已用 git apply -p1 应用"; APPLIED=1
  elif git apply --3way --whitespace=nowarn "$PATCH_FILE" 2>/dev/null; then
    echo "    已用 git apply --3way 应用"; APPLIED=1
  else
    warn "git apply 失败, 回退 patch -p1 -F3"
    if patch -p1 -F3 --no-backup-if-mismatch < "$PATCH_FILE"; then APPLIED=1; fi
    # 统计残留 rej
    REJ="$(find . -name '*.rej' -not -path './.git/*' | wc -l)"
    if [ "$REJ" != "0" ]; then
      echo "    ---- 冲突文件 ----"
      find . -name '*.rej' -not -path './.git/*' | sed 's/^/    /'
      die "风驰补丁有 $REJ 个文件冲突 (.rej), 需要人工处理"
    fi
  fi
  [ "$APPLIED" = "1" ] || die "风驰补丁无法应用"

  # 结构校验: hmbird 实现必须在, AOSP sched_ext 必须已被移除
  [ -f kernel/sched/hmbird/hmbird.c ] || die "缺少 kernel/sched/hmbird/hmbird.c, 风驰补丁不完整"
  [ -f include/linux/sched/sched_ext.h ] || die "缺少 include/linux/sched/sched_ext.h"
  [ -f kernel/sched/ext.c ] && die "AOSP kernel/sched/ext.c 仍在"
  [ -f include/linux/sched/ext.h ] && die "AOSP include/linux/sched/ext.h 仍在"

  # 补丁应把 CONFIG_SCHED_CLASS_EXT 换成 CONFIG_HMBIRD_SCHED
  if grep -q '^CONFIG_HMBIRD_SCHED=y' arch/arm64/configs/gki_defconfig; then
    echo "    CONFIG_HMBIRD_SCHED=y 已就位"
  else
    warn "补丁未写入 CONFIG_HMBIRD_SCHED=y, 手工补上"
    echo 'CONFIG_HMBIRD_SCHED=y' >> arch/arm64/configs/gki_defconfig
  fi
  echo "    hmbird 源文件: $(ls kernel/sched/hmbird/ | wc -l) 个"
else
  warn "APPLY_FENGCHI=0 -> 不打风驰补丁 (将保留 AOSP sched_ext, 无 HMBIRD/风驰)"
fi

# --------------------------- 3. 集成 FolkSU ----------------------------------
if [ "$APPLY_KSU" = "1" ]; then
log "集成 FolkSU 内核侧代码 (tag $FOLKSU_TAG)"
KSU_DIR="$PWD/KernelSU"
if [ ! -d "$KSU_DIR/.git" ]; then
  rm -rf "$KSU_DIR"
  # 需要完整历史: kernel/Kbuild 用 rev-list --count HEAD 计算 KSU_VERSION
  git clone --quiet "$FOLKSU_REPO" "$KSU_DIR"
fi
git -C "$KSU_DIR" fetch --tags --quiet 2>/dev/null || true
git -C "$KSU_DIR" checkout --quiet "$FOLKSU_TAG" 2>/dev/null \
  || warn "无法切到 $FOLKSU_TAG, 使用默认分支"
KSU_COMMITS="$(git -C "$KSU_DIR" rev-list --count HEAD)"
KSU_VERSION="$((30000 + KSU_COMMITS))"

# 不要把嵌套仓库算进内核仓库的改动里
grep -qxF '/KernelSU/' .git/info/exclude 2>/dev/null || echo '/KernelSU/' >> .git/info/exclude
grep -qxF '/drivers/kernelsu' .git/info/exclude 2>/dev/null || echo '/drivers/kernelsu' >> .git/info/exclude

# kernel/include/uapi -> ../../uapi, 在该布局下解析到 KernelSU/uapi
[ -L KernelSU/kernel/include/uapi ] || ln -sfn ../../uapi KernelSU/kernel/include/uapi
[ -f KernelSU/kernel/include/uapi/supercall.h ] || die "FolkSU uapi 布局异常"

# 与 KernelSU 官方 setup.sh 完全相同的接入方式
ln -sfn ../KernelSU/kernel drivers/kernelsu
grep -q 'kernelsu' drivers/Makefile || printf '\nobj-$(CONFIG_KSU) += kernelsu/\n' >> drivers/Makefile
grep -q 'drivers/kernelsu/Kconfig' drivers/Kconfig \
  || sed -i '/^endmenu/i source "drivers/kernelsu/Kconfig"' drivers/Kconfig

KSU_UAPI="$(sed -n 's/.*KERNEL_SU_UAPI_VERSION *= *\([0-9]\+\).*/\1/p' KernelSU/uapi/supercall.h | head -1)"
[ "$KSU_UAPI" = "5" ] || die "FolkSU UAPI=$KSU_UAPI, 与管理器 0.1.0-beta2 (uapi: 5) 不匹配"
echo "    KERNEL_SU_UAPI_VERSION = $KSU_UAPI"
echo "    KSU_VERSION = $KSU_VERSION   (管理器 APK 为 32783)"
echo "    受信任管理器证书: size=$KSU_EXPECTED_SIZE sha256=${KSU_EXPECTED_HASH:0:16}..."
else
  warn "APPLY_KSU=0 -> 内核不带 KernelSU (配合 init_boot 里的 kernelsu.ko LKM root 使用)"
fi

# --------------------------- 4. 锁定内核版本后缀 ------------------------------
log "锁定内核版本后缀: $LOCALVERSION_SUFFIX"
sed -i "s|^CONFIG_LOCALVERSION=.*|CONFIG_LOCALVERSION=\"${LOCALVERSION_SUFFIX}\"|" arch/arm64/configs/gki_defconfig
if grep -q '^CONFIG_LOCALVERSION_AUTO=' arch/arm64/configs/gki_defconfig; then
  sed -i 's|^CONFIG_LOCALVERSION_AUTO=.*|CONFIG_LOCALVERSION_AUTO=n|' arch/arm64/configs/gki_defconfig
else
  echo 'CONFIG_LOCALVERSION_AUTO=n' >> arch/arm64/configs/gki_defconfig
fi
# 去掉 setlocalversion 末尾的 ${scm_version}, 避免 -dirty/+ 污染 vermagic
sed -i 's/\${scm_version}//' scripts/setlocalversion

# --------------------------- 5. SuSFS (默认关闭) -----------------------------
if [ "$APPLY_SUSFS" = "1" ]; then
  log "应用 SuSFS 补丁 (实验性)"
  SUSFS_DIR="$WORKDIR/susfs4ksu"
  [ -d "$SUSFS_DIR" ] || git clone --depth=1 https://github.com/ShirkNeko/susfs4ksu.git "$SUSFS_DIR" || true
  P="$SUSFS_DIR/kernel_patches/50_add_susfs_in_gki-android15-6.6.patch"
  if [ -f "$P" ]; then
    cp "$SUSFS_DIR"/kernel_patches/fs/* fs/ 2>/dev/null || true
    cp "$SUSFS_DIR"/kernel_patches/include/linux/* include/linux/ 2>/dev/null || true
    patch -p1 -F3 --no-backup-if-mismatch < "$P" || warn "SuSFS 内核补丁有冲突"
    K="$SUSFS_DIR/kernel_patches/KernelSU/10_enable_susfs_for_ksu.patch"
    if [ -f "$K" ]; then
      ( cd KernelSU && patch -p1 -F3 --no-backup-if-mismatch < "$K" ) \
        || warn "SuSFS 与 FolkSU 的联动补丁冲突 (FolkSU 已重构目录结构)"
    fi
    cat >> arch/arm64/configs/gki_defconfig <<'EOF'
CONFIG_KSU_SUSFS=y
CONFIG_KSU_SUSFS_SUS_PATH=y
CONFIG_KSU_SUSFS_SUS_MOUNT=y
CONFIG_KSU_SUSFS_SUS_KSTAT=y
CONFIG_KSU_SUSFS_TRY_UMOUNT=y
CONFIG_KSU_SUSFS_SPOOF_UNAME=y
CONFIG_KSU_SUSFS_ENABLE_LOG=y
CONFIG_KSU_SUSFS_HIDE_KSU_SUSFS_SYMBOLS=y
CONFIG_KSU_SUSFS_OPEN_REDIRECT=y
EOF
  else
    warn "未找到 SuSFS 补丁, 跳过"
  fi
fi

# --------------------------- 6. 追加 defconfig -------------------------------
log "追加 defconfig 配置项"
cat >> arch/arm64/configs/gki_defconfig <<'EOF'
CONFIG_TMPFS_XATTR=y
CONFIG_TMPFS_POSIX_ACL=y
CONFIG_CC_OPTIMIZE_FOR_PERFORMANCE=y
EOF
if [ "$APPLY_KSU" = "1" ]; then
  echo 'CONFIG_KSU=y' >> arch/arm64/configs/gki_defconfig
fi
if [ "$APPLY_SUSFS" != "1" ] && [ "$APPLY_KSU" = "1" ]; then
  echo 'CONFIG_KSU_SUSFS=n' >> arch/arm64/configs/gki_defconfig
fi
if [ "$ENABLE_BTF" = "1" ]; then
  log "启用 BTF (给第三方 scx 调度器用)"
  command -v pahole >/dev/null 2>&1 || die "ENABLE_BTF=1 但没有 pahole (apt install dwarves)"
  cat >> arch/arm64/configs/gki_defconfig <<'EOF'
CONFIG_DEBUG_INFO_BTF=y
CONFIG_DEBUG_INFO_BTF_MODULES=y
CONFIG_MODULE_ALLOW_BTF_MISMATCH=y
EOF
  pahole --version | sed 's/^/    pahole /'
fi

# --------------------------- 7. 编译 -----------------------------------------
log "开始编译 (jobs=$JOBS, clang-$CLANG_VER, target=$BUILD_TARGET)"
MAKE_ARGS=(
  -j"$JOBS"
  "LLVM=-$CLANG_VER"
  ARCH=arm64
  CROSS_COMPILE=aarch64-linux-gnu-
  CROSS_COMPILE_ARM32=arm-linux-gnueabihf-
  CC=clang
  LD=ld.lld
  HOSTCC=clang
  HOSTLD=ld.lld
  O=out
  KCFLAGS="-O2 -Wno-error"
  KSU_EXPECTED_SIZE="$KSU_EXPECTED_SIZE"
  KSU_EXPECTED_HASH="$KSU_EXPECTED_HASH"
)

make "${MAKE_ARGS[@]}" gki_defconfig

# 关键配置校验
if [ "$APPLY_FENGCHI" = "1" ]; then EXT_CFG=CONFIG_HMBIRD_SCHED; else EXT_CFG=CONFIG_SCHED_CLASS_EXT; fi
CHECKS="CONFIG_KPROBES CONFIG_EXT4_FS $EXT_CFG"
[ "$APPLY_KSU" = "1" ] && CHECKS="CONFIG_KSU $CHECKS"
[ "$ENABLE_BTF" = "1" ] && CHECKS="$CHECKS CONFIG_DEBUG_INFO_BTF"
for c in $CHECKS; do
  grep -q "^${c}=y" out/.config || die "$c 未启用 (内核配置异常)"
  echo "    $c = y"
done
grep -m1 '^CONFIG_LOCALVERSION=' out/.config | sed 's/^/    /'

make "${MAKE_ARGS[@]}" "$BUILD_TARGET"

IMAGE="$PWD/out/arch/arm64/boot/Image"
[ -f "$IMAGE" ] || die "编译失败: 找不到 $IMAGE"

# --------------------------- 8. 校验 + 输出 ----------------------------------
log "校验产物"
UTS="$(strings -a "$IMAGE" | grep -m1 '^Linux version' || true)"
echo "    $UTS"
# 注意: 后缀以 '-' 开头, 必须用 -- 终止选项解析, 否则 grep 把它当参数而报错(误报)
[ -n "$UTS" ] && { echo "$UTS" | grep -q -- "$LOCALVERSION_SUFFIX" \
  || warn "UTS_RELEASE 未包含 $LOCALVERSION_SUFFIX"; }
for m in hmbird hmbird_sched KernelSU; do
  printf '    标记 %-14s %s 次\n' "$m" "$(grep -a -o "$m" "$IMAGE" | wc -l)"
done
[ "$APPLY_FENGCHI" = "1" ] && { grep -aq 'hmbird_sched' "$IMAGE" \
  || warn "内核里没有 hmbird_sched, 风驰可能没编进去"; }

mkdir -p "$WORKDIR/out"
cp "$IMAGE" "$WORKDIR/out/Image"
{
  # 注意: 内核是带 O=out 编的, kernel.release 在 out/include/config/ 下
  echo "UTS_RELEASE=$(cat out/include/config/kernel.release 2>/dev/null || cat include/config/kernel.release 2>/dev/null || echo unknown)"
  echo "KERNEL_REPO=$KERNEL_REPO"
  echo "KERNEL_BRANCH=$KERNEL_BRANCH"
  echo "KERNEL_SOURCE_HEAD=$SRC_HEAD"
  echo "FOLKSU_TAG=$FOLKSU_TAG"
  echo "KSU_VERSION=${KSU_VERSION:-N/A (未集成 KernelSU)}"
  echo "KSU_UAPI=${KSU_UAPI:-N/A (未集成 KernelSU)}"
  echo "KSU_EXPECTED_SIZE=$KSU_EXPECTED_SIZE"
  echo "KSU_EXPECTED_HASH=$KSU_EXPECTED_HASH"
  echo "FENGCHI=$APPLY_FENGCHI"
  echo "SUSFS=$APPLY_SUSFS"
  echo "BUILT_AT=$(date -u '+%Y-%m-%d %H:%M:%S UTC')"
} | tee "$WORKDIR/out/build-info.txt"

log "编译完成 -> $WORKDIR/out/Image"
