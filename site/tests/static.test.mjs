import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile,stat,readdir} from 'node:fs/promises';
import {createHash} from 'node:crypto';
const root=new URL('../',import.meta.url),native=new URL('assets/native/',root);
test('demo catalog identifies real files, folder entries and a Word preview derived from its original',async()=>{
 const catalog=JSON.parse(await readFile(new URL('assets/files/catalog.json',root),'utf8'));
 assert.equal(catalog.files.length,12);
 for(const entry of catalog.files){
  const bytes=await readFile(new URL(entry.path,native));
  assert.equal(bytes.length,entry.size,entry.name);
  assert.equal(createHash('sha256').update(bytes).digest('hex'),entry.sha256,entry.name);
  if(entry.bytesPath)assert.deepEqual(await readFile(new URL(entry.bytesPath,native)),bytes,'binary transport preserves the original HTML bytes');
  if(entry.mime==='application/pdf')assert.equal(bytes.subarray(0,5).toString(),'%PDF-');
  if(entry.name.endsWith('.zip')||entry.name.endsWith('.docx'))assert.equal(bytes.subarray(0,2).toString(),'PK');
  if(entry.name.endsWith('.mov'))assert.match(bytes.subarray(0,16).toString(),/ftyp/);
  if(entry.name.endsWith('.wav')){assert.equal(bytes.subarray(0,4).toString(),'RIFF');assert.equal(bytes.subarray(8,12).toString(),'WAVE');}
 }
 const folder=catalog.folders[0];assert.equal(folder.children.length,6);
 for(const child of folder.children){const bytes=await readFile(new URL(child.path,native));assert.equal(createHash('sha256').update(bytes).digest('hex'),catalog.files.find(f=>f.name===child.name).sha256);}
 const word=catalog.files.find(f=>f.name==='出行计划.docx');assert.equal(catalog.previews.word.sourceSHA256,word.sha256);
 assert.match(await readFile(new URL(catalog.previews.word.path,native),'utf8'),/目的地：海边的小镇/);
});
test('all twelve types use existing native renderings and real source files',async()=>{
 const manifest=JSON.parse(await readFile(new URL('manifest.json',native),'utf8'));
 assert.equal(manifest.items.length,12);assert.equal(manifest.padding,32);assert.match(manifest.renderer,/CardSurface/);
 for(const item of [...manifest.items,...(manifest.extraItems||[])]){assert.ok(item.width>100&&item.height>100);assert.ok((await stat(new URL(item.file,native))).isFile());
 for(const path of [item.left,item.right,item.compactLeft,item.compactRight,item.source,...(item.pages||[]).flatMap(p=>[p.left,p.right,p.surfaceLeft,p.surfaceRight])]){
 const data=await readFile(new URL(path,native));assert.ok(data.subarray(0,3).toString('hex')==='ffd8ff'||data.subarray(1,4).toString()==='PNG'||(data.subarray(0,4).toString()==='RIFF'&&data.subarray(8,12).toString()==='WEBP'),path);assert.ok(data.length>100,path);
 }
 }
 for(const kind of ['document','word'])assert.equal(manifest.items.find(i=>i.kind===kind).pages.length,3);
});
test('project Pages paths and published assets are self contained',async()=>{
 const html=await readFile(new URL('index.html',root),'utf8');assert.match(html,/<h1(?:\s[^>]*)?>/);assert.match(html,/releases\/download\/v1\.7\.16\/ClampEverything-1\.7\.16-arm64\.dmg/);assert.match(html,/aria-live="polite"/);
 for(const match of html.matchAll(/(?:src|href)="(\.\/[^"#]+)"/g))assert.ok((await stat(new URL(match[1],root))).isFile());
 assert.doesNotMatch(html,/(?:src|href)="\/(?!\/)/);assert.doesNotMatch(html,/<script[^>]+src="https?:/);
 async function bytes(url){let n=0;for(const entry of await readdir(url,{withFileTypes:true})){const child=new URL(encodeURIComponent(entry.name)+(entry.isDirectory()?'/':''),url);n+=entry.isDirectory()?await bytes(child):(await stat(child)).size;}return n;}
 assert.ok(await bytes(new URL('assets/',root))<50_000_000);
 const css=await readFile(new URL('style.css',root),'utf8');assert.match(css,/prefers-reduced-motion:\s*reduce/);
 const js=await readFile(new URL('main.js',root),'utf8');assert.doesNotMatch(js,/function playDemo|function paperPage|class="native-note"/,'no generated document window or scripted capture');
});

test('usage screenshots are actual recorded interactions and PDF text comes from the matching original',async()=>{
 const page=await readFile(new URL('assets/files/field-notes.html',root),'utf8');
 const provenance=JSON.parse(await readFile(new URL('assets/usage/provenance.json',root),'utf8'));
 assert.match(provenance.method,/real Option/);assert.equal(provenance.files.length,3);
 for(const name of provenance.files){assert.ok((await stat(new URL('assets/usage/'+name,root))).size>1000);assert.ok(page.includes('../usage/'+name));}
 assert.match(page,/id="usage-title"/);assert.match(page,/loading="lazy"/);
 const text=JSON.parse(await readFile(new URL('assets/files/旅行手记.text.json',root),'utf8'));
 const pdf=await readFile(new URL('assets/files/旅行手记.pdf',root));
 assert.equal(text.sourceSHA256,createHash('sha256').update(pdf).digest('hex'));
 assert.equal(text.pages.length,3);assert.equal(text.pages[0][0].text,'旅行手记');
 for(const line of text.pages.flat()){assert.ok(line.text.trim());assert.ok(line.x>=0&&line.y>=0&&line.width>0&&line.height>0&&line.x+line.width<=1.001&&line.y+line.height<=1.001);}
});

test('promotional media uses the actual recording and two independently clippable photographs',async()=>{
 const manifest=JSON.parse(await readFile(new URL('manifest.json',native),'utf8'));
 const movie=manifest.items.find(item=>item.kind==='video');assert.equal(movie.duration,109);assert.equal(movie.title,'屏幕夹子-实际操作演示.mov');
 assert.ok((await stat(new URL(movie.file,native))).size>1_000_000);
 const photos=[...manifest.items,...manifest.extraItems].filter(item=>item.kind==='photo');assert.equal(photos.length,2);assert.notEqual(photos[0].file,photos[1].file);assert.notEqual(photos[0].left,photos[1].left);
 const captions=JSON.parse(await readFile(new URL('media-source/promotional/captions.json',root),'utf8'));
 assert.equal(captions[0][0],0);assert.equal(captions.at(-1)[1],movie.duration);for(let i=1;i<captions.length;i++)assert.equal(captions[i][0],captions[i-1][1]);
 const page=await readFile(new URL('assets/files/field-notes.html',root),'utf8');assert.ok(page.includes(movie.title));assert.match(page,/<video controls playsinline preload="none"/);assert.match(page,/href="#promo-title"/);
});
