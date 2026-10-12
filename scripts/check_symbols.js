#!/usr/bin/env node
/*
 * 链接期兜底: fs/susfs.c 以 extern 引用的函数, 必须有人真正"定义"。
 *
 * 为什么需要: 上游对接补丁 (10_enable_susfs_for_ksu.patch) 里定义了
 * susfs_is_current_ksu_domain() 等符号, 而我们没有采用那个补丁, 于是
 * 每一个都可能在链接期变成 undefined symbol —— 每漏一个就是一轮 CI。
 *
 * 判定"已定义"的依据: 某个文件里出现 <类型> <名字>(  形式的定义/声明。
 * 只要在内核补丁(新增行)、FinaSU 源码、或适配层任意一处出现即认为有人提供
 * (真正重复定义的概率极低, 且编译器会立刻报出来)。
 *
 * 用法: check_symbols.js <susfs.c> <50补丁> <KSU源码根> <适配层>
 * 退出码 1 = 有符号无人提供
 */
'use strict';
const fs = require('fs'), path = require('path');
const [susfsC, patch50, ksuRoot, adapter] = process.argv.slice(2);
if (!susfsC || !patch50 || !ksuRoot || !adapter) {
  console.error('用法: check_symbols.js <susfs.c> <50补丁> <KSU根> <适配层>');
  process.exit(2);
}

// 1) 收集 susfs.c 里 extern 声明的函数名
const src = fs.readFileSync(susfsC, 'utf8');
const wanted = new Set();
for (const m of src.matchAll(/^extern\s+[^;]*?([A-Za-z_][A-Za-z_0-9]*)\s*\(/gm)) wanted.add(m[1]);
// susfs.h 里也可能有 (本项目为空, 保留以防上游改名)
// 2) 内核补丁只会新增行, 只看 "+" 开头的行
const patch = fs.readFileSync(patch50, 'utf8');
const patchAdded = patch.split('\n').filter(l => l.startsWith('+') && !l.startsWith('+++')).join('\n');
const inPatch = (s) => new RegExp('[^A-Za-z_0-9]' + s + '\\s*\\(').test(patchAdded);

// 3) 递归收集 KSU 源码 (排除我们自己生成的适配层, 单独判定)
const files = [];
(function walk(d) {
  for (const e of fs.readdirSync(d, { withFileTypes: true })) {
    const p = path.join(d, e.name);
    if (e.isDirectory()) { if (e.name !== '.git' && e.name !== 'include') walk(p); }
    else if (/\.(c|h)$/.test(e.name)) files.push(p);
  }
})(ksuRoot);
const ksuText = files.filter(f => f !== adapter).map(f => fs.readFileSync(f, 'utf8')).join('\n');
const inKsu = (s) => new RegExp('(^|[^A-Za-z_0-9])' + s + '\\s*\\(').test(ksuText);

const adapterText = fs.readFileSync(adapter, 'utf8');
const inAdapter = (s) => new RegExp('(^|[^A-Za-z_0-9])' + s + '\\s*\\(').test(adapterText);

const missing = [];
for (const s of [...wanted].sort()) {
  if (inPatch(s) || inKsu(s) || inAdapter(s)) continue;
  missing.push(s);
}
console.log(`    检查 ${wanted.size} 个 extern 符号`);
if (missing.length) {
  console.error('    无人提供的符号: ' + missing.join(', '));
  process.exit(1);
}
console.log('    全部有提供者 ✓');
