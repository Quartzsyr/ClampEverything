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
  await library.ensure(item);
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


test('startup reads only the catalog; concurrent hover, open and capture share one verified download',async()=>{
 const native=new URL('../assets/native/',import.meta.url),originalFetch=globalThis.fetch,requests=[];
 let unblock;const gate=new Promise(resolve=>unblock=resolve);
 globalThis.fetch=async path=>{const url=path instanceof URL?path:new URL(path);requests.push(url.pathname);if(!url.pathname.endsWith('/catalog.json'))await gate;return new Response(await readFile(url));};
 const library=new FileLibrary(path=>new URL(path,native));
 try{
  const manifest=JSON.parse(await readFile(new URL('manifest.json',native),'utf8'));await library.load(manifest.items);
  assert.equal(requests.length,1);assert.ok([...library.records.values()].every(record=>record.file===null));
  const movie=manifest.items.find(item=>item.kind==='video');assert.equal(movie.fileId,library.get(movie).sha256);
  const hover=library.prefetch(movie),open=library.ensure(movie),capture=library.ensure(movie);
  assert.equal(requests.length,2);unblock();const records=await Promise.all([hover,open,capture]);
  assert.equal(records[0],records[1]);assert.equal(records[1],records[2]);assert.equal(records[0].file.size,library.get(movie).size);assert.equal(library.pending.size,0);
 }finally{unblock();globalThis.fetch=originalFetch;for(const record of library.records.values())if(record.file)URL.revokeObjectURL(record.href);}
});

test('a failed speculative read stays isolated and retries successfully on the next open',async()=>{
 const native=new URL('../assets/native/',import.meta.url),originalFetch=globalThis.fetch;let fail=true,reads=0;
 globalThis.fetch=async path=>{const url=path instanceof URL?path:new URL(path);if(!url.pathname.endsWith('/catalog.json')){reads++;if(fail)return new Response('corrupted original');}return new Response(await readFile(url));};
 const library=new FileLibrary(path=>new URL(path,native));
 try{const manifest=JSON.parse(await readFile(new URL('manifest.json',native),'utf8'));await library.load(manifest.items);const pdf=manifest.items.find(item=>item.kind==='document');
  assert.equal(await library.prefetch(pdf),null);assert.equal(reads,2);assert.equal(library.get(pdf).file,null);assert.equal(library.failures.size,1);assert.equal(library.pending.size,0);
  fail=false;const original=await library.ensure(pdf);assert.ok(original.file instanceof File);assert.equal(library.failures.size,0);assert.equal(reads,3);
 }finally{globalThis.fetch=originalFetch;for(const record of library.records.values())if(record.file)URL.revokeObjectURL(record.href);}
});
