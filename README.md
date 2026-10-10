# Ace6 GKI 6.6 内核构建工程（风驰 + FolkSU）

面向 **一加 Ace 6（PLQ110 / 代号 `ossi` / SM8750 "sun" / Android 16 ColorOS 16）** 的
GKI 6.6 内核自动构建工程。云编译（GitHub Actions），本机无需 Linux。

## 产出的内核是什么

| 项目 | 取值 | 说明 |
|---|---|---|
| 源码基线 | `OnePlusOSS/android_kernel_common_oneplus_sm8750`<br>分支 `oneplus/sm8750_b_16.0.0_ace_6` | 一加官方开源内核源码（提交 `65b954a`，PLQ110_16.0.9.401 CN01） |
| 内核版本 | `6.6.118-android15-8-o-4k` | 与出厂 `vendor_dlkm` 里模块的 `vermagic` **逐字一致**，保证厂商模块能加载 |
| 风驰内核 | OPlus **HMBIRD** 调度类（`CONFIG_HMBIRD_SCHED=y`） | 由 `patches/fengchi.patch` 移植；官方 common 树只有 `include/linux/sched/hmbird.h`，缺 `kernel/sched/hmbird/` 实现 |
| Root | **FolkSU**（KernelSU fork）内核侧代码，`KERNEL_SU_UAPI_VERSION = 5` | 与 `FolkSU_v0.1.0-beta2_32783-release.apk` 完全匹配 |
| 管理器信任 | 证书 `size=0x2cc`、`sha256=2d89b50a…8458` | 从你的 APK 实测提取，编进内核后该 APK 被识别为**受信任管理器** |
| 刷机包 | AnyKernel3 zip（只含 `Image`） | `BLOCK=boot`、A/B 双槽、有独立 `init_boot` 时只换内核不动 ramdisk |

## 目录结构

```
.github/workflows/build.yml   GitHub Actions 构建流程
scripts/build.sh              主编译脚本（本地/Linux 也能直接跑）
scripts/make_ak3.sh           打包 AnyKernel3 刷机包
scripts/apk_sign.py           从 APK 提取 KernelSU 侧管理器签名 (size, sha256)
ak3/anykernel.sh              Ace 6 专用 AnyKernel3 刷机脚本
patches/fengchi-ace6.patch    风驰内核补丁（已重基到 ace_6，0 reject）
patches/fengchi.patch         上游原始风驰补丁（保留备查）
```

### 风驰补丁是怎么来的

上游 `fengchi.patch` 的基线是 cctv18 fork 的 **一加13** 分支，直接打到官方 **ace_6** 分支上有
**19 个 hunk 冲突**（涉及 6 个文件，都在 ACK LTS 频繁改动的区域）。`fengchi-ace6.patch` 是重基
结果，19 处冲突逐条解决并验证：

| 文件 | 冲突 hunk | 处理方式 |
|---|---|---|
| `include/linux/cpufreq.h` | 1 | **丢弃** —— ace_6 里 `store/show_scaling_governor` 声明已存在 |
| `include/linux/sched.h` | 2 | 去掉 `sched_prop`/`scx` KABI 槽；**保留 `task_dma_buf_info` 在槽 3**（ace_6 新增，出厂厂商模块按此偏移编译） |
| `kernel/fork.c` | 2 | `hmbird_free()` 替换；标签合并时**保留 ace_6 新增的 `bad_fork_cleanup_dmabuf:`** |
| `kernel/time/tick-sched.c` | 1 | 插入 `android_vh_tick_nohz_idle_stop_tick_handler()` 调用 |
| `kernel/sched/debug.c` | 1 | `ext.enabled` → `hmbird.enabled` + 2 个新 `__PS` |
| `kernel/sched/core.c` | 12 | `sched_move_task` 一处**丢弃**（ace_6 已是展开版）；其余为 `hmbird_tasks_lock`、`__setscheduler_prio`、cgroup hmbird deadline 等逐条移植 |

生成后经校验：`git apply --reject` → **0 reject / 0 failed hunk**，所有文件 `#ifdef/#endif` 配平。


## 怎么用（云编译）

1. 打开仓库 → **Actions** → 左侧 **Build Ace6 GKI 6.6 (fengchi + FolkSU)** → **Run workflow**。
2. 保持默认即可：

   | 输入 | 默认 | 含义 |
   |---|---|---|
   | `apply_fengchi` | ✅ true | 移植风驰（HMBIRD 调度类）。关掉就退回 AOSP sched_ext |
   | `apply_susfs` | ⬜ false | SuSFS 隐藏补丁。**默认关闭**：FolkSU 的 `kernel/Kconfig` 里没有任何 `SUSFS` 项，且其目录结构已重构，`susfs4ksu` 的联动补丁大概率冲突 |
   | `localversion` | `-android15-8-o-4k` | 内核版本后缀，**别乱改**，改了会和厂商模块 vermagic 不匹配 |
   | `ksu_expected_size` / `ksu_expected_hash` | 已填好 | 受信任管理器证书。换 APK 时用 `scripts/apk_sign.py` 重新提取 |
   | `build_target` | `Image` | 只编内核镜像，最快；改 `all` 会连模块一起编 |

3. 等构建完成（首次约 30–60 分钟），在 run 页面底部下载 **`Ace6-GKI-6.6-fengchi-FolkSU-<run>`** 工件，里面的 zip 即可刷入。

## 怎么用（本地 Linux）

```bash
INSTALL_DEPS=1 bash scripts/build.sh          # 自动装 clang-18 等依赖
bash scripts/make_ak3.sh work/out/Image dist  # 打成刷机包
```

## 换一个 FolkSU 管理器 APK

```bash
python3 scripts/apk_sign.py /path/to/NewManager.apk
# 把输出的 size / sha256 填给 workflow 的 ksu_expected_size / ksu_expected_hash
```

## 刷入须知

- 刷前**务必备份**官方 `boot.img`（用 `fastboot getvar current-slot` 确认槽位）。
- 本包只替换 `boot` 分区里的 `Image`，**不碰 ramdisk / init_boot / vbmeta**。
- 该机有独立 `init_boot` 分区，AnyKernel3 会自动走 `split_boot`/`flash_boot` 分支。
- 刷完开机后用 **FolkSU 管理器**确认 Root；管理器里应显示版本 `32783-5`。
- 验证风驰是否生效：`adb shell ls /proc/hmbird_sched/`（需要设备 DTBO 里有
  `/soc/oplus,hmbird/version_type = "HMBIRD_OGKI"`，一加 Ace 6 官方固件自带）。

## 两个已知的技术要点

1. **风驰补丁会删掉 AOSP 的 sched_ext**。`fengchi.patch` 是 OPlus 在自家树上的分支 diff：
   删除 `kernel/sched/ext.c`、`include/linux/sched/ext.h`、`tools/sched_ext/**`，
   把 `SCHED_EXT`(7) 改名为 `SCHED_HMBIRD`(7)、`CONFIG_SCHED_CLASS_EXT` 改为 `CONFIG_HMBIRD_SCHED`。
   这**就是一加官方的做法**（官方树自带 `include/linux/sched/hmbird.h`），所以"保留风驰"与
   "保留 sched_ext" 二者不可兼得。
2. **SuSFS 默认不开**。要做隐藏请先在 FolkSU 树里确认 SUSFS 接入点，或改用支持 SuSFS 的 KSU 分支。
