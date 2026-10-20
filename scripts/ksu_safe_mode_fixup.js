#!/usr/bin/env node
// 修正 FinaSU(KernelSU) 音量键安全模式的误触发:
//   原逻辑: if (val) count++  -> 按住音量下的"自动重复"(val==2) 也被当成一次按下,
//           按住约 0.3 秒就能凑出 3 次以上, 阈值只要 3 -> "没按"也会进安全模式。
//   新逻辑: if (val == 1) count++
//           - 只统计首次按下(val==1), 自动重复(val==2)不再计数
//           - 不引入任何新内核 API 调用(kprobe 上下文里保持最小副作用)
// 用法: node ksu_safe_mode_fixup.js <KSU源码根>
'use strict';
const fs = require('fs'), path = require('path');

const root = process.argv[2];
if (!root) { console.error('用法: node ksu_safe_mode_fixup.js <KSU源码根>'); process.exit(1); }

const target = path.join(root, 'kernel/runtime/ksud_integration.c');
if (!fs.existsSync(target)) { console.error('[x] 找不到 ' + target); process.exit(1); }

let src = fs.readFileSync(target, 'utf8');

if (src.includes('if (val == 1)')) {
    console.log('[=] 音量键安全模式修正已在, 跳过');
    process.exit(0);
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
    indent + 'if (val == 1) {' +
    indent + '    /* 只统计首次按下(val==1); 自动重复(val==2)不计, 避免误进安全模式 */';

const replaced = tail.replace(oldCond, newCond);
if (replaced === tail || !replaced.includes('if (val == 1)')) {
    console.error('[x] 替换未生效');
    process.exit(1);
}

fs.writeFileSync(target, src.slice(0, ai) + replaced);
console.log('[+] 已修正: 音量键安全模式只统计首次按下(val==1), 自动重复不再计数');
