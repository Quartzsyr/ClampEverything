import test from 'node:test';
import assert from 'node:assert/strict';
import {releaseModel,fetchReleases,historyHTML,summaryHTML,API,RELEASES} from '../assets/release-data.js';
const asset=(name,n)=>({name,download_count:n,size:1048576,browser_download_url:`${RELEASES}/download/v2/${name}`});
const release=(tag,assets,extras={})=>({tag_name:tag,name:`Release ${tag}`,html_url:`${RELEASES}/tag/${tag}`,published_at:'2026-10-16T01:00:00Z',assets,...extras});
test('download totals count only DMGs; zero, unknown, drafts and repeated versions stay distinct',()=>{
 const model=releaseModel([release('v2',[asset('arm64.dmg',0),asset('intel.DMG',3),asset('app.dmg.sha256',90),asset('icon.png',100)]),release('v1',[asset('old.dmg',4)]),release('v1',[asset('duplicate.dmg',99)]),release('draft',[asset('draft.dmg',99)],{draft:true})],'v2');
 assert.equal(model.totalDownloads,7);assert.equal(model.releases.length,2);assert.equal(model.releases[0].downloads,3);assert.match(summaryHTML(model),/7/);
 const unknown=releaseModel([release('v1',[asset('bad.dmg',undefined)])],'v1');assert.equal(unknown.totalDownloads,null);assert.match(summaryHTML(unknown),/—/);
 const zero=releaseModel([release('v1',[asset('real.dmg',0)])],'v1');assert.equal(zero.totalDownloads,0);assert.match(historyHTML(zero),/0 次下载/);
});
test('rendered release names are escaped and unsafe download links are excluded',()=>{
 const model=releaseModel([release('v1',[asset('app.dmg',5),{...asset('evil.dmg',8),browser_download_url:'javascript:alert(1)'}],{name:'<img src=x onerror=alert(1)>',prerelease:true})],null);
 assert.equal(model.totalDownloads,5);const html=historyHTML(model);assert.match(html,/&lt;img/);assert.doesNotMatch(html,/javascript:|<img/);assert.match(html,/预发布/);assert.match(html,/target="_top"/);
});
test('GitHub pagination contributes every version and latest comes from its dedicated endpoint',async()=>{
 const calls=[];const model=await fetchReleases({fetcher:async url=>{calls.push(url);if(url.endsWith('/latest'))return new Response(JSON.stringify({tag_name:'v1'}));if(url.endsWith('page=2'))return new Response(JSON.stringify([release('v0',[asset('old.dmg',2)])]));return new Response(JSON.stringify([release('v1',[asset('app.dmg',4)])]),{headers:{Link:`<${API}?per_page=100&page=2>; rel="next"`}});}});
 assert.equal(model.totalDownloads,6);assert.equal(model.releases.length,2);assert.equal(model.latestTag,'v1');assert.equal(calls.length,3);
 await assert.rejects(fetchReleases({fetcher:async()=>new Response('{}',{status:403})}),/GitHub 403/);
});
