#!/usr/bin/env node
/*
 * 校验 SUSFS Kconfig 菜单片段的结构合法性。
 *
 * 为什么需要: kconfig 的语法很脆 —— 只要某个 config 块漏了 "help",
 * 它后面那些以 "- " 开头的说明行就会被当成语句解析, 在 olddefconfig
 * 阶段才报 "syntax error / unknown statement \"-\""。而那时 CI 已经跑了
 * 十几分钟。这里提前把它拦下来。
 */
'use strict';
const fs = require('fs');
const f = process.argv[2];
if (!f) { console.error('用法: check_kconfig.js <片段文件>'); process.exit(2); }
const lines = fs.readFileSync(f, 'utf8').split('\n');
let errs = 0;
const bad = (m) => { console.error('  [kconfig] ' + m); errs++; };

// 1) 顶格以 "- " 开头 => 语句位置出现说明行, 必是缺 help
lines.forEach((l, i) => { if (/^- /.test(l)) bad(`第 ${i + 1} 行顶格以 "- " 开头(应在 help 块内): ${JSON.stringify(l)}`); });

// 2) 逐个 config 块检查: 有 bool/tristate 就必须有 help
let cfg = 0, hlp = 0;
for (let i = 0; i < lines.length; i++) {
  if (!/^config /.test(lines[i])) continue;
  cfg++;
  let j = i + 1, hasHelp = false, hasBool = false, hasProp = false;
  for (; j < lines.length; j++) {
    const t = lines[j];
    if (/^(config|menu|endmenu)\b/.test(t)) break;
    if (/^\s+help\s*$/.test(t)) hasHelp = true;
    if (/^\s+(bool|tristate)\b/.test(t)) hasBool = true;
    if (/^\s+(bool|tristate|depends|default|select|range|prompt)\b/.test(t)) hasProp = true;
  }
  if (hasHelp) hlp++;
  // help 之后只能是缩进更深的说明文本
  if (!hasHelp && hasBool) bad(`${lines[i]}: 有 bool 却没有 help (其说明行会被当成语句)`);
  if (!hasProp) bad(`${lines[i]}: 没有任何属性行(bool/depends/default 等)`);
}

// 3) menu/endmenu 配平
let depth = 0;
for (const t of lines) {
  if (/^menu\b/.test(t)) depth++;
  else if (/^endmenu\b/.test(t)) depth--;
  if (depth < 0) bad('endmenu 多于 menu');
}
if (depth !== 0) bad('menu/endmenu 不配平, 差 ' + depth);
if (cfg !== hlp) bad(`config 数(${cfg}) 与 help 数(${hlp}) 不一致`);

if (errs) { console.error(`  [kconfig] 共 ${errs} 处问题`); process.exit(1); }
console.log(`    Kconfig 结构 OK (config=${cfg}, help=${hlp}, menu 配平)`);
