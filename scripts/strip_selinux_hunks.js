#!/usr/bin/env node
/*
 * 从 SUSFS 内核补丁里摘掉 security/selinux/* 的几处改动。
 *
 * 原因: FinaSU(KernelSU fork) **自己已经实现**了 SELinux 隐藏, 而且是更彻底的做法:
 *   - selinux_hide.c : 运行时用 ksu_patch_text 改 sel_handle_status_ops->open,
 *                      并用 LSM hook 拦 selinux_setprocattr
 *   - avc_spoof.c    : kprobe 拦 slow_avc_audit 做 AVC 日志伪装
 * 而 SUSFS 补丁又在**源码层**改同一批函数(selinuxfs.c / hooks.c / avc.c)。
 * 两层叠在同一个函数上, SELinux 对外行为就与"只带 FinaSU"的原包不同了 ——
 * 会被春秋检测这类工具判为"可疑 SELinux"。
 *
 * 因此把 SUSFS 对这三个文件的改动整体摘除, 让 SELinux 行为回到原包一致
 * (由 FinaSU 自己的机制负责)。SUSFS 其余功能(path/mount/kstat/uname/
 * bootconfig/map 隐藏、符号隐藏)全部保留。
 *
 * 用法: strip_selinux_hunks.js <原补丁> <输出补丁>
 */
'use strict';
const fs = require('fs');
const [src, dst] = process.argv.slice(2);
if (!src || !dst) { console.error('用法: strip_selinux_hunks.js <原补丁> <输出补丁>'); process.exit(2); }

// 要摘除的文件 (相对内核源码根)
const DROP = [
  'security/selinux/avc.c',
  'security/selinux/hooks.c',
  'security/selinux/selinuxfs.c',
];

const text = fs.readFileSync(src, 'utf8');
const parts = text.split(/^(?=diff --git )/m);
const kept = [], dropped = [];
for (const p of parts) {
  if (!p.trim()) continue;
  const m = /^diff --git a\/(\S+) b\/(\S+)/.exec(p);
  if (m && DROP.includes(m[2])) { dropped.push(m[2]); continue; }
  kept.push(p);
}
if (dropped.length !== DROP.length) {
  console.error(`!! 预期摘除 ${DROP.length} 个文件, 实际只匹配到 ${dropped.length}: ${dropped.join(', ')}`);
  process.exit(1);
}
// 完整性自检: 摘除后这些文件不应再出现在补丁里
for (const f of DROP) {
  if (new RegExp('^diff --git a/' + f.replace(/[.*+?^${}()|[\]\\]/g, '\\$&') + ' ', 'm').test(kept.join(''))) {
    console.error('!! 摘除后仍残留: ' + f); process.exit(1);
  }
}
fs.writeFileSync(dst, kept.join(''));
console.log(`    已摘除 SUSFS 对 SELinux 的改动: ${dropped.join(', ')}`);
console.log(`    补丁: ${text.length} -> ${kept.join('').length} 字节`);
