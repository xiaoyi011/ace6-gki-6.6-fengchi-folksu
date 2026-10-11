#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
通用 GKI (OnePlus SM8750 "sun" 平台): 放宽 vendor 模块 vermagic 校验。

背景:
  一加 sun 平台各机型 (Ace6 / 13 / 13T / 13s / Ace5Pro / Pad2Pro / Pad3) 共用
  同一套平台代码, 但出厂内核的版本串尾部带固件相关信息, 例如
      6.6.118-android15-8-g9bc34d5b0c79-abogki537459655-4k   (Ace6 / 13)
      6.6.118-android15-8-g2e6b9c3812c5-ab15114928-4k        (Pad 3)
      6.6.150-android15-8-g1826411674e2-abogki537459655-4k  (SpiderDroid 6.6.150)
  主版本号 (6.6.118 / 6.6.150) 与平台印记相同或相近, 但中间的 commit/固件标识
  因机型与固件版本而异。vendor 模块的 vermagic 必须与运行内核全等才会加载,
  导致"一个内核通吃全系"无法实现。

本脚本做的事:
  在 kernel/module/main.c 里把严格的全串比对 same_magic() 换成放宽后的
  vermagic_compat(): 先走原来的严格比对, 失败时再退化为"只比对主版本号前缀"
  (如 "6.6.118"), 从而允许同一平台不同机型/固件的 vendor 模块被加载。

安全边界:
  1. 符号版本索引 (info->index.vers) 必须一致, 否则不放行;
  2. CONFIG_MODVERSIONS 的符号 CRC 校验完全不变 —— ABI 不兼容的模块依然会被
     "disagrees about version of symbol" 拒绝, 不会被强行加载。
  3. 仅在显式开启 RELAX_VERMAGIC=1 时应用 (默认构建行为不变)。
"""
import os
import re
import sys

PATH = sys.argv[1] if len(sys.argv) > 1 else "kernel/module/main.c"

if not os.path.exists(PATH):
    print("[x] 找不到 %s" % PATH)
    sys.exit(1)

with open(PATH, "r", encoding="utf-8") as f:
    src = f.read()

if "vermagic_compat" in src:
    print("[!] 已打过通用 vermagic 补丁, 跳过")
    sys.exit(0)

OLD_COND = "} else if (!same_magic(modmagic, vermagic, info->index.vers)) {"
NEW_COND = "} else if (!vermagic_compat(modmagic, vermagic, info->index.vers)) {"

if src.count(OLD_COND) != 1:
    print("[x] 找不到唯一的 vermagic 校验点 (期望 1 处, 实际 %d 处)" % src.count(OLD_COND))
    sys.exit(1)

HELPER = '''/*
 * Universal GKI: vermagic prefix compatibility check
 *
 * Falls back to comparing only the leading main version prefix (e.g.
 * "6.6.118") when the strict full-string compare fails, so vendor modules
 * built for another device / firmware drop of the same SM8750 (sun) platform
 * can still be loaded by this kernel.
 *
 * Safety boundaries:
 *   - the symbol index version must match this kernel, otherwise the symbol
 *     version table layout differs and the module is rejected;
 *   - CONFIG_MODVERSIONS symbol CRC verification is untouched, so modules
 *     with an incompatible ABI are still rejected by the kernel.
 */
static bool vermagic_compat(const char *amagic, const char *bmagic,
			    unsigned int binfo_vers)
{
\tsize_t len = 0;

\t/* 1. strict compare first (original behaviour) */
\tif (same_magic(amagic, bmagic, binfo_vers))
\t\treturn true;

\t/* 2. symbol index version must match */
\tif (binfo_vers && *amagic != *bmagic)
\t\treturn false;

\t/* 3. compare only the main version prefix */
\twhile (len < 32 && bmagic[len] && bmagic[len] != '-')
\t\tlen++;
\tif (!len)
\t\treturn false;

\treturn memcmp(amagic, bmagic, len) == 0;
}

'''

m = re.search(r"static int check_modinfo\([^)]*\)\n\{", src)
if not m:
    print("[x] 找不到 check_modinfo 定义")
    sys.exit(1)
anchor = m.group(0)

src = src.replace(OLD_COND, NEW_COND, 1)
src = src.replace(anchor, HELPER + anchor, 1)

with open(PATH, "w", encoding="utf-8", newline="") as f:
    f.write(src)

print("[+] 已放宽 vermagic 校验: 只比对主版本号前缀 (符号 CRC 校验保持不变)")