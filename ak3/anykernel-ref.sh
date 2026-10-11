#!/bin/bash
# =============================================================================
# AnyKernel3 刷机脚本 —— 一加 Ace 6 (PLQ110 / ossi / SM8750 "sun")
# 【本脚本用于社区"参考内核" 6.6.150 g1826411674e2-abogki537459655-4k】
#
# 已实测: 该 Image 在本机 fastboot boot 成功进入系统(uname 6.6.150-...),
#         /proc/hmbird_sched 存在(风驰 HMBIRD 生效), 701 个模块全部加载。
#
# 注意 root 方案:
#   该内核【内置 SukiSU】(com.resukisu.resukisu), 会抢先占用内核侧 root 接口,
#   导致 init_boot 里的 FolkSU kernelsu.ko 判定"已加载"而跳过 ->
#   FolkSU 管理器(me.yuki.folksu)管不到它。它的 su 是可用(uid=0)。
#   若要 FolkSU 管理器可管理, 请刷我们自编译的 Image(build.sh apply_ksu=false)。
#
# 分区布局要点:
#   * A/B 双槽 (IS_SLOT_DEVICE=1)
#   * 内核 Image 在 boot 分区, 一阶段 ramdisk 在独立的 init_boot 分区
#     -> 有 init_boot 时只做 split_boot/flash_boot, 绝不动 ramdisk, 不碰 vbmeta
#   * do.modules=0: 厂商模块留在 vendor_dlkm / system_dlkm
# =============================================================================

### AnyKernel setup
# global properties
properties() { '
kernel.string=Ace6 verified-boot kernel 6.6.150 (fengchi HMBIRD, built-in SukiSU)
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
'; } # end properties

### AnyKernel install
## boot shell variables
BLOCK=boot
IS_SLOT_DEVICE=1
RAMDISK_COMPRESSION=auto
PATCH_VBMETA_FLAG=0
NO_MAGISK_CHECK=1
NO_VBMETA_PARTITION_PATCH=1

# import functions/variables and setup patching - see for reference (DO NOT REMOVE)
. tools/ak3-core.sh

ui_print " "
ui_print "*******************************"
ui_print " Ace6 6.6.150 verified kernel"
ui_print "*******************************"
ui_print " "
ui_print "[i] Device : OnePlus Ace 6 (PLQ110 / ossi / SM8750)"
ui_print "[i] Kernel : 6.6.150-android15-8-g1826411674e2-abogki537459655-4k"
ui_print "[i] Sched  : fengchi HMBIRD (/proc/hmbird_sched)"
ui_print "[i] Root   : built-in SukiSU (NOT the FolkSU manager)"
ui_print " "
ui_print "[i] 机型: 一加 Ace 6"
ui_print "[i] 内核: 6.6.150 (已实测可启动) + 风驰 HMBIRD"
ui_print "[i] Root: 内核内置 SukiSU, 不是 FolkSU 管理器那套"
ui_print "[i] 想要 FolkSU 管理器可管理, 请刷自编译 Image"
ui_print " "

# 规避部分机型文件系统 I/O 延迟导致的二进制执行异常 (cctv18 同款加固)
sync
sleep 0.5
chmod -R 755 $AKHOME/tools

# boot install
# 该机有独立 init_boot 分区: 内核在 boot, ramdisk 在 init_boot,
# 因此只要存在 init_boot 就只替换内核, 绝不重打 ramdisk。
if [ -L "/dev/block/bootdevice/by-name/init_boot_a" ] || [ -L "/dev/block/by-name/init_boot_a" ]; then
    ui_print "[i] 检测到独立 init_boot, 仅替换内核 Image, 保留 ramdisk"
    split_boot
    flash_boot
else
    ui_print "[i] 未检测到 init_boot, 走完整流程"
    split_boot
    if [ -f "split_img/ramdisk.cpio" ]; then
        unpack_ramdisk
        write_boot
    else
        flash_boot
    fi
fi
## end boot install

ui_print " "
ui_print "[OK] 刷入完成, 重启即可 (风驰已生效: ls /proc/hmbird_sched)"
ui_print "[OK] Done. Reboot. fengchi active: ls /proc/hmbird_sched"
ui_print " "
