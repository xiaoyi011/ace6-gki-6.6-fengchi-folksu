#!/usr/bin/env node
/*
 * 摘除 50 补丁写入 fs/exec.c 的 sucompat 钩子块。
 *
 * 原因: 该块要求
 *     int ksu_handle_execveat(int *fd, struct filename **, void *argv, void *envp, int *flags)
 * 而 FinaSU 的等价实现是 kprobe 式的
 *     long ksu_handle_execveat_sucompat(const char __user **, int orig_nr, struct pt_regs *)
 * 二者架构不同、无法桥接; FinaSU 自身 sucompat 已完成 su 检测,
 * 两套并存会互相打架并导致链接失败, 故整体摘除。
 *
 * 注意: fs/exec.c 里还有其它 #ifdef CONFIG_KSU_SUSFS 块(不同的, 必须保留),
 * 所以要按"块内容"挑选真正要摘的那几个, 不能只取第一个。
 */
'use strict';
const fs = require('fs');
const p = process.argv[2] || 'fs/exec.c';
const lines = fs.readFileSync(p, 'utf8').split('\n');
const n0 = lines.length;

/** 找出所有 #ifdef CONFIG_KSU_SUSFS ... #endif 块(含嵌套计数) */
function blocks() {
  const out = [];
  for (let i = 0; i < lines.length; i++) {
    if (lines[i].trim() !== '#ifdef CONFIG_KSU_SUSFS') continue;
    let depth = 0, end = -1;
    for (let j = i; j < lines.length; j++) {
      const t = lines[j].trim();
      if (/^#\s*if(def|ndef)?\b/.test(t)) depth++;
      else if (/^#\s*endif\b/.test(t)) { depth--; if (depth === 0) { end = j; break; } }
    }
    if (end > i) out.push({ start: i, end });
  }
  return out;
}

/** 摘除"块内含 needle"的那个块 */
function cutBlock(needle, label) {
  for (const b of blocks()) {
    const body = lines.slice(b.start, b.end + 1).join('\n');
    if (!body.includes(needle)) continue;
    console.log(`    fs/exec.c: 摘除 ${label} (行 ${b.start + 1}-${b.end + 1})`);
    lines.splice(b.start, b.end - b.start + 1);
    return true;
  }
  return false;
}

let ok = 0;
if (cutBlock('ksu_handle_execveat', 'extern 声明块')) ok++;
if (cutBlock('is_su_session', 'is_su_session 声明块')) ok++;
if (cutBlock('orig_flow', 'su 检测块')) ok++;
if (cutBlock('ksu_handle_post_execveat_sucompat', 'post_execveat 调用块')) ok++;

const out = lines.join('\n');
if (out.includes('ksu_handle_execveat') || out.includes('is_su_session')) {
  console.error('!! fs/exec.c 仍有残留 ksu_handle_execveat / is_su_session');
  process.exit(1);
}
if (ok !== 4) {
  console.error(`!! fs/exec.c 只摘除 ${ok}/4 个块 (补丁结构变化?)`);
  process.exit(1);
}
fs.writeFileSync(p, out);
console.log(`    fs/exec.c sucompat 钩子已摘除 (${n0} -> ${lines.length} 行)`);
