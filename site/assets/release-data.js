// Public GitHub Release asset counters; no click tracking or estimated counts.
// https://docs.github.com/en/rest/releases/releases
export const API = 'https://api.github.com/repos/Quartzsyr/ClampEverything/releases';
export const RELEASES = 'https://github.com/Quartzsyr/ClampEverything/releases';
const escape = value => String(value).replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const count = value => Number.isSafeInteger(value) && value >= 0 ? value : null;
const sum = values => values.every(value=>value!==null) ? values.reduce((a,b)=>a+b,0) : null;
export const number = value => value===null ? '—' : new Intl.NumberFormat('zh-CN').format(value);
export const date = value => Number.isFinite(Date.parse(value)) ? new Intl.DateTimeFormat('zh-CN',{year:'numeric',month:'2-digit',day:'2-digit',timeZone:'Asia/Shanghai'}).format(new Date(value)) : '日期未知';
export const size = bytes => `${(bytes/1048576).toFixed(1)} MiB`;
function safeURL(value,prefix) { try {const url=new URL(value);return url.href.startsWith(prefix) && url.protocol==='https:' ? url.href : null;} catch {return null;} }
export function releaseModel(raw,latestTag,fetchedAt=new Date().toISOString()) {
  if(!Array.isArray(raw))throw new Error('Invalid release response');
  const seen=new Set();
  const releases=raw.filter(r=>r&&!r.draft&&r.published_at&&typeof r.tag_name==='string').map(r=>{
    const url=safeURL(r.html_url,`${RELEASES}/tag/`);if(!url||seen.has(r.tag_name))return null;seen.add(r.tag_name);
    const assets=(r.assets||[]).filter(a=>a&&/\.dmg$/i.test(a.name||'')).map(a=>({name:a.name,url:safeURL(a.browser_download_url,`${RELEASES}/download/`),downloads:count(a.download_count),size:count(a.size)})).filter(a=>a.url);
    return {tag:r.tag_name,name:String(r.name||r.tag_name),url,publishedAt:r.published_at,prerelease:!!r.prerelease,assets,downloads:sum(assets.map(a=>a.downloads))};
  }).filter(Boolean).sort((a,b)=>Date.parse(b.publishedAt)-Date.parse(a.publishedAt));
  return {fetchedAt,latestTag,releases,totalDownloads:sum(releases.map(r=>r.downloads))};
}
export async function fetchReleases({fetcher=fetch,headers={}}={}) {
  const read=async url=>{const response=await fetcher(url,{cache:'no-store',headers:{Accept:'application/vnd.github+json',...headers},signal:AbortSignal.timeout(10000)});if(!response.ok)throw new Error(`GitHub ${response.status}`);return response;};
  const latestPromise=read(`${API}/latest`).then(r=>r.json()).then(r=>r.tag_name).catch(()=>null);
  const all=[];let url=`${API}?per_page=100`;const visited=new Set();
  while(url){if(visited.has(url))throw new Error('Repeated release page');visited.add(url);const response=await read(url),entries=await response.json();if(!Array.isArray(entries))throw new Error('Invalid release page');all.push(...entries);
    const next=/<([^>]+)>;\s*rel="next"/.exec(response.headers.get('Link')||'')?.[1];
    if(next&&!next.startsWith(`${API}?`))throw new Error('Unexpected pagination URL');url=next||null;
  }
  return releaseModel(all,await latestPromise);
}
export function summaryHTML(model) {
  return `<span>GitHub 安装包累计下载 <strong>${number(model.totalDownloads)}</strong> 次</span><a href="#release-history">${number(model.releases.length)} 个版本 ↓</a>`;
}
export function historyHTML(model) {
  if(!model.releases.length)return '<li class="release-empty">暂未发布版本，<a href="'+RELEASES+'" target="_blank" rel="noopener">前往 GitHub 查看 ↗</a></li>';
  return model.releases.map(r=>`<li class="release-row"><div class="release-details"><div class="release-version"><a href="${escape(r.url)}" target="_blank" rel="noopener">${escape(r.tag)}</a>${r.tag===model.latestTag?'<span class="release-badge">最新版</span>':''}${r.prerelease?'<span class="release-badge preview">预发布</span>':''}<time datetime="${escape(r.publishedAt)}">${date(r.publishedAt)}</time></div><p class="release-name">${escape(r.name)}</p><p class="release-count">${number(r.downloads)} 次下载${r.assets.length===1&&r.assets[0].size!==null?' · '+size(r.assets[0].size):''}</p></div><div class="release-files">${r.assets.length?r.assets.map(a=>`<a class="release-file" href="${escape(a.url)}" target="_top" title="${escape(a.name)}">下载${r.assets.length>1?' '+(/arm64/i.test(a.name)?'Apple Silicon':/x64|intel/i.test(a.name)?'Intel':escape(a.name)):''} ↓</a>`).join(''):`<a class="release-file" href="${escape(r.url)}" target="_blank" rel="noopener">查看版本 ↗</a>`}</div></li>`).join('');
}
