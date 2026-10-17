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
  assert.equal(dragFiles.length,1);assert.ok(dragFiles[0] instanceof File);assert.equal(dragFiles[0].name,'我的桌面收纳计划.docx');
  assert.deepEqual(new Uint8Array(await dragFiles[0].arrayBuffer()),new Uint8Array(await readFile(new URL(item.file,native))));
  assert.equal(library.resolveDrag(transfer,manifest.items),item);
  data.set('application/x-clamp-file',JSON.stringify({kind:'word',id:'unrelated-file'}));assert.equal(library.resolveDrag(transfer,manifest.items),undefined);
 }finally{globalThis.fetch=originalFetch;for(const entry of library.records.values())URL.revokeObjectURL(entry.href);}
});

test('edited text is its own real TXT File and survives verified drag resolution',async()=>{
 const library=new FileLibrary(path=>new URL(path,'https://example.com/assets/native/'));
 const text='新写下的便笺\n准备带上相机。',item=await library.createText(text,{kind:'note',width:284,height:224},'我的备忘录.txt');
 const record=await library.ensure(item);
 assert.ok(record.file instanceof File);assert.equal(record.file.name,'我的备忘录.txt');assert.equal(await record.file.text(),text);assert.equal(record.file.size,new TextEncoder().encode(text).length);
 const data=new Map(),transfer={items:{add:file=>assert.equal(file,record.file)},setData:(k,v)=>data.set(k,v),getData:k=>data.get(k)};
 library.writeDrag(transfer,item);assert.equal(library.resolveDrag(transfer,[]),item);assert.equal(data.get('text/uri-list'),record.href);
 assert.notEqual((await library.createText('另一段文字',item)).fileId,item.fileId);URL.revokeObjectURL(record.href);
});
