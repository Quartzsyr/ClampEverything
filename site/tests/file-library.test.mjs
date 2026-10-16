import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {FileLibrary} from '../file-library.js';

test('drag export contains the original File bytes and resolves only verified file identities',async()=>{
 const native=new URL('../assets/native/',import.meta.url);
 const originalFetch=globalThis.fetch;
 globalThis.fetch=async path=>new Response(await readFile(path instanceof URL?path:new URL(path)));
 const library=new FileLibrary(path=>new URL(path,native));
 try{
  const manifest=JSON.parse(await readFile(new URL('manifest.json',native),'utf8'));
  await library.load(manifest.items);
  const item=manifest.items.find(item=>item.kind==='word'),data=new Map(),dragFiles=[];
  const transfer={items:{add:file=>dragFiles.push(file)},setData:(type,value)=>data.set(type,value),getData:type=>data.get(type)};
  library.writeDrag(transfer,item);
  assert.equal(dragFiles.length,1);assert.ok(dragFiles[0] instanceof File);assert.equal(dragFiles[0].name,'出行计划.docx');
  assert.deepEqual(new Uint8Array(await dragFiles[0].arrayBuffer()),new Uint8Array(await readFile(new URL(item.file,native))));
  assert.equal(library.resolveDrag(transfer,manifest.items),item);
  data.set('application/x-clamp-file',JSON.stringify({kind:'word',id:'unrelated-file'}));assert.equal(library.resolveDrag(transfer,manifest.items),undefined);
 }finally{globalThis.fetch=originalFetch;for(const entry of library.records.values())URL.revokeObjectURL(entry.href);}
});
