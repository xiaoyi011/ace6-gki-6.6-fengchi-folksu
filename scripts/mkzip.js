'use strict';
// 用 Node 生成 zip, 规避 GitHub Actions 对 zip 命令的限流 (exit 15)
const fs=require('fs'), path=require('path'), zlib=require('zlib');
function crc32(buf){
  let c, table=crc32.t;
  if(!table){ table=crc32.t=[]; for(let n=0;n<256;n++){ c=n; for(let k=0;k<8;k++) c=c&1?0xEDB88320^(c>>>1):c>>>1; table[n]=c>>>0; } }
  let crc=0xFFFFFFFF;
  for(let i=0;i<buf.length;i++) crc=table[(crc^buf[i])&0xFF]^(crc>>>8);
  return (crc^0xFFFFFFFF)>>>0;
}
function dosTime(d){
  const t=((d.getHours()<<11)|(d.getMinutes()<<5)|(d.getSeconds()/2))&0xFFFF;
  const dt=(((d.getFullYear()-1980)<<9)|((d.getMonth()+1)<<5)|d.getDate())&0xFFFF;
  return {t,dt};
}
function zipDir(srcDir, outFile, prefix){
  const files=[];
  (function walk(d){
    for(const e of fs.readdirSync(d,{withFileTypes:true})){
      const p=path.join(d,e.name);
      if(e.isDirectory()) walk(p);
      else if(e.isFile()) files.push(p);
    }
  })(srcDir);
  files.sort();
  const chunks=[], central=[];
  let offset=0;
  const now=dosTime(new Date());
  for(const f of files){
    const rel=path.relative(srcDir,f).split(path.sep).join('/');
    const name=(prefix?prefix+'/':'')+rel;
    const data=fs.readFileSync(f);
    const comp=zlib.deflateRawSync(data,{level:9});
    const useDeflate=comp.length<data.length;
    const body=useDeflate?comp:data;
    const method=useDeflate?8:0;
    const crc=crc32(data);
    const nameBuf=Buffer.from(name,'utf8');
    const lh=Buffer.alloc(30);
    lh.writeUInt32LE(0x04034b50,0);
    lh.writeUInt16LE(20,4);        // version needed
    lh.writeUInt16LE(0x0800,6);    // flags: UTF-8
    lh.writeUInt16LE(method,8);
    lh.writeUInt16LE(now.t,10);
    lh.writeUInt16LE(now.dt,12);
    lh.writeUInt32LE(crc,14);
    lh.writeUInt32LE(body.length,18);
    lh.writeUInt32LE(data.length,22);
    lh.writeUInt16LE(nameBuf.length,26);
    lh.writeUInt16LE(0,28);
    chunks.push(lh,nameBuf,body);
    const ch=Buffer.alloc(46);
    ch.writeUInt32LE(0x02014b50,0);
    ch.writeUInt16LE(20,4); ch.writeUInt16LE(20,6);
    ch.writeUInt16LE(0x0800,8);
    ch.writeUInt16LE(method,10);
    ch.writeUInt16LE(now.t,12); ch.writeUInt16LE(now.dt,14);
    ch.writeUInt32LE(crc,16);
    ch.writeUInt32LE(body.length,20);
    ch.writeUInt32LE(data.length,24);
    ch.writeUInt16LE(nameBuf.length,28);
    ch.writeUInt16LE(0,30); ch.writeUInt16LE(0,32);
    ch.writeUInt16LE(0,34); ch.writeUInt16LE(0,36);
    ch.writeUInt32LE(0,38);
    ch.writeUInt32LE(offset,42);
    central.push(ch,nameBuf);
    offset += lh.length+nameBuf.length+body.length;
  }
  const cdBuf=Buffer.concat(central);
  const eocd=Buffer.alloc(22);
  eocd.writeUInt32LE(0x06054b50,0);
  eocd.writeUInt16LE(0,4); eocd.writeUInt16LE(0,6);
  eocd.writeUInt16LE(files.length,8);
  eocd.writeUInt16LE(files.length,10);
  eocd.writeUInt32LE(cdBuf.length,12);
  eocd.writeUInt32LE(offset,16);
  eocd.writeUInt16LE(0,20);
  fs.writeFileSync(outFile, Buffer.concat([...chunks, cdBuf, eocd]));
  return {count:files.length, size:fs.statSync(outFile).size};
}
const [,,src,out,prefix]=process.argv;
if(!src||!out){ console.error('用法: node mkzip.js <目录> <输出zip> [前缀]'); process.exit(2); }
const r=zipDir(src,out,prefix);
console.log('✅ 已生成 '+out+'  ('+r.count+' 个文件, '+(r.size/1048576).toFixed(2)+'MB)');
