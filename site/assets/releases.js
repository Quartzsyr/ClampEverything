import {fetchReleases,summaryHTML,historyHTML,date,size} from './release-data.js';

const cacheKey='clamp-release-stats-v1',ttl=10*60*1000;
const status=document.querySelector('#release-status'),refresh=document.querySelector('#refresh-releases');
let current=null,busy=false;
try{current=JSON.parse(document.querySelector('#release-data').textContent);}catch{}
function render(model,source){
  current=model;document.querySelector('#download-stats').innerHTML=summaryHTML(model);document.querySelector('#release-list').innerHTML=historyHTML(model);
  const latest=model.releases.find(r=>r.tag===model.latestTag&&!r.prerelease),asset=latest?.assets.find(a=>/arm64/i.test(a.name))||latest?.assets[0];
  if(asset){document.querySelector('#desktop-download').href=asset.url;const notes=document.querySelector('.actions .release');notes.href=latest.url;notes.textContent=`${latest.tag} 更新说明 ↗`;document.querySelector('.version').textContent=`${latest.tag} · Apple Silicon · macOS 14+${asset.size===null?'':' · '+size(asset.size)}`;}
  status.textContent=`${source} · ${date(model.fetchedAt)}`;status.title=`数据同步时间：${new Date(model.fetchedAt).toLocaleString('zh-CN',{timeZone:'Asia/Shanghai'})}`;
}
async function update(force=false){
  if(busy)return;busy=true;refresh.disabled=true;
  try{
    try{const cache=JSON.parse(localStorage.getItem(cacheKey)),age=Date.now()-Date.parse(cache?.fetchedAt);if(Array.isArray(cache?.releases)&&Number.isFinite(age)&&age>=0&&(!current||Date.parse(cache.fetchedAt)>=Date.parse(current.fetchedAt))){render(cache,'上次同步数据');if(!force&&age<ttl){render(cache,'已缓存 GitHub 数据');return;}}}catch{}
    status.textContent='正在同步 GitHub…';const model=await fetchReleases();render(model,'已同步 GitHub');try{localStorage.setItem(cacheKey,JSON.stringify(model));}catch{}
  }catch{
    if(current)render(current,'上次同步数据');else status.textContent='暂时无法读取 GitHub，仍可下载或查看 Release';
  }finally{busy=false;refresh.disabled=false;}
}
refresh.addEventListener('click',()=>update(true));update();
