import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile,stat,readdir} from 'node:fs/promises';
const root=new URL('../',import.meta.url),native=new URL('assets/native/',root);
test('all twelve types use existing native renderings and real source files',async()=>{
 const manifest=JSON.parse(await readFile(new URL('manifest.json',native),'utf8'));
 assert.equal(manifest.items.length,12);assert.equal(manifest.padding,32);assert.match(manifest.renderer,/CardSurface/);
 for(const item of manifest.items){assert.ok(item.width>100&&item.height>100);assert.ok((await stat(new URL(item.file,native))).isFile());
 for(const path of [item.left,item.right,item.compactLeft,item.compactRight,item.source,...(item.pages||[]).flatMap(p=>[p.left,p.right,p.surfaceLeft,p.surfaceRight])]){
 const data=await readFile(new URL(path,native));assert.equal(data.subarray(1,4).toString(),'PNG',path);assert.ok(data.length>100,path);
 }
 }
 for(const kind of ['document','word'])assert.equal(manifest.items.find(i=>i.kind===kind).pages.length,3);
});
test('project Pages paths and published assets are self contained',async()=>{
 const html=await readFile(new URL('index.html',root),'utf8');assert.match(html,/<h1>/);assert.match(html,/releases\/latest/);assert.match(html,/aria-live="polite"/);
 for(const match of html.matchAll(/(?:src|href)="(\.\/[^"#]+)"/g))assert.ok((await stat(new URL(match[1],root))).isFile());
 assert.doesNotMatch(html,/(?:src|href)="\/(?!\/)/);assert.doesNotMatch(html,/<script[^>]+src="https?:/);
 async function bytes(url){let n=0;for(const entry of await readdir(url,{withFileTypes:true})){const child=new URL(encodeURIComponent(entry.name)+(entry.isDirectory()?'/':''),url);n+=entry.isDirectory()?await bytes(child):(await stat(child)).size;}return n;}
 assert.ok(await bytes(new URL('assets/',root))<12_000_000);
 const css=await readFile(new URL('style.css',root),'utf8');assert.match(css,/prefers-reduced-motion:\s*reduce/);
 const js=await readFile(new URL('main.js',root),'utf8');assert.doesNotMatch(js,/function playDemo|function paperPage|class="native-note"/,'no generated document window or scripted capture');
});
