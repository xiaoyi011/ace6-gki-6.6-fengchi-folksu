#!/bin/bash
# =============================================================================
# AnyKernel3 刷机脚本 —— 一加 Ace 6 (PLQ110 / ossi)
# 内核: GKI 6.6 + 风驰(HMBIRD/scx) + FolkSU(KernelSU fork, UAPI 5)
#
# 分区布局要点:
#   * 该机是 A/B 双槽 (IS_SLOT_DEVICE=1)
#   * 内核 Image 在 boot 分区, 一阶段 ramdisk 在独立的 init_boot 分区
#     -> 因此只做 split_boot/flash_boot, 绝不重打 ramdisk, 避免破坏 AVB/系统
#   * do.modules=0: 厂商模块留在 vendor_dlkm, 由内核 vermagic 对齐后加载
# =============================================================================

properties() { '
kernel.string=Ace6 GKI 6.6 (fengchi + FolkSU)
do.devicecheck=0
do.modules=0
do.systemless=1
do.cleanup=1
do.cleanuponabort=0
device.name1=
device.name2=
device.name3=
device.name4=
device.name5=
supported.versions=
supported.patchlevels=
supported.vendorpatchlevels=
'; }

BLOCK=boot
IS_SLOT_DEVICE=1
RAMDISK_COMPRESSION=auto
PATCH_VBMETA_FLAG=0
NO_MAGISK_CHECK=1
NO_VBMETA_PARTITION_PATCH=1

. tools/ak3-core.sh

ui_print " "
ui_print "*******************************"
ui_print " Ace6 GKI 6.6 + 风驰 + FolkSU"
ui_print "*******************************"
ui_print " "
ui_print "[i] 机型: OnePlus Ace 6 (PLQ110 / ossi / SM8750)"
ui_print "[i] 内核: GKI 6.6 官方 ace_6 源码 + 风驰(HMBIRD/scx)"
ui_print "[i] Root: FolkSU (KernelSU, UAPI=5)"
ui_print " "

if [ -L "/dev/block/bootdevice/by-name/init_boot_a" ] || [ -L "/dev/block/by-name/init_boot_a" ]; then
    ui_print "[i] 检测到独立 init_boot 分区, 仅替换内核, 保留 ramdisk"
    split_boot
    flash_boot
else
    ui_print "[i] 未检测到 init_boot, 走完整 ramdisk 流程"
    dump_boot
    write_boot
fi

ui_print " "
ui_print "[✓] 刷入完成, 重启后请用 FolkSU 管理器确认 Root 状态"
ui_print "[✓] Done. Reboot and open the FolkSU manager."
ui_print " "
