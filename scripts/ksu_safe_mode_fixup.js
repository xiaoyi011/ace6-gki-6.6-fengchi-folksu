#!/usr/bin/env node
// 修正 FinaSU(KernelSU) 音量键安全模式的误触发:
//   原逻辑: if (val) count++  -> 按住音量下的"自动重复"(val==2) 也被当成一次按下,
//           按住约 1 秒就能凑出十几个计数, 阈值只要 3 -> 没按也会进安全模式。
//   新逻辑: if (val == 1 && ktime_get_boottime_seconds() < 60) count++
//           - 只统计首次按下(val==1), 不再统计自动重复(val==2)
//           - 只在开机后 60 秒内采样, 日常使用期调音量不会累积
// 用法: node ksu_safe_mode_fixup.js <KSU源码根>
'use strict';
const fs = require('fs'), path = require('path');

const root = process.argv[2];
if (!root) { console.error('用法: node ksu_safe_mode_fixup.js <KSU源码根>'); process.exit(1); }

const target = path.join(root, 'kernel/runtime/ksud_integration.c');
if (!fs.existsSync(target)) { console.error('[x] 找不到 ' + target); process.exit(1); }

let src = fs.readFileSync(target, 'utf8');
const MARK = 'ktime_get_boottime_seconds() < 60';

if (src.includes(MARK)) {
    console.log('[=] 音量键安全模式修正已在, 跳过');
    process.exit(0);
}

if (!src.includes('#include <linux/ktime.h>')) {
    if (src.includes('#include <linux/kprobes.h>')) {
        src = src.replace('#include <linux/kprobes.h>',
            '#include <linux/kprobes.h>\n#include <linux/ktime.h>');
    } else {
        src = src.replace('#include <linux/printk.h>',
            '#include <linux/printk.h>\n#include <linux/ktime.h>');
    }
    if (!src.includes('#include <linux/ktime.h>')) {
        console.error('[x] 无法插入 linux/ktime.h');
        process.exit(1);
    }
}

const anchor = 'pr_info("KEY_VOLUMEDOWN val: %d\\n", val);';
const ai = src.indexOf(anchor);
if (ai < 0) { console.error('[x] 找不到 KEY_VOLUMEDOWN 打印锚点, 源码结构变了'); process.exit(1); }

const tail = src.slice(ai);
const oldCond = /(\r?\n[ \t]*)if \(val\) \{/;
const m = oldCond.exec(tail);
if (!m) { console.error('[x] 锚点之后找不到 "if (val) {", 源码结构变了'); process.exit(1); }

const indent = m[1];
const newCond =
    indent + 'if (val == 1 && ktime_get_boottime_seconds() < 60) {' +
    indent + '    /* 只计首次按下(val==1), 且仅开机后 60 秒内采样: ' +
    indent + '     * 自动重复(val==2)与日常调音量不再累计, 避免误进安全模式 */';

const replaced = tail.replace(oldCond, newCond);
if (replaced === tail || !replaced.includes(MARK)) {
    console.error('[x] 替换未生效');
    process.exit(1);
}

fs.writeFileSync(target, src.slice(0, ai) + replaced);
console.log('[+] 已修正: 音量键安全模式只统计首次按下(val==1) 且限开机后 60 秒内');
