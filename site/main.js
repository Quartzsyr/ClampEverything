import { HoldGesture } from './hold-gesture.js';
import { HINGE, MATERIALS, clamp, hingeAngle, pickupSample, placement } from './motion.js';

const $ = (selector, root = document) => root.querySelector(selector);
const $$ = (selector, root = document) => [...root.querySelectorAll(selector)];
const objects = $('#objects'), desktop = $('#desktop'), dialog = $('#info-dialog');
const BASE = new URL('.', import.meta.url);
const asset = name => new URL(`assets/${name}`, BASE).href;
const reduced = matchMedia('(prefers-reduced-motion: reduce)');
const state = { objects: new Map(), sequence: 0, capture: false, alt: false, drag: null, pickup: null,
  point: { x: innerWidth / 2, y: innerHeight / 2 }, tour: 0, z: 10, sizes: {}, motion: !reduced.matches, theme: 'day', brass: false };
const gesture = new HoldGesture();
const TYPES = {
  photo: { title: '山间湖泊.png', label: '照片', hint: '照片保持原比例，像一张轻轻弯曲的相纸。', size: [232, 200] },
  note: { title: '周末的小计划', label: '文字', hint: '一闪而过的念头，夹成一张棉纸便笺。', size: [206, 275] },
  document: { title: '旅行手记.pdf', label: 'PDF', hint: '滚轮或页角翻页，纸页从左侧装订线向外翻。', size: [190, 280] },
  word: { title: '出行计划.docx', label: 'Word 文稿', hint: 'Word 文稿也可以直接阅读，按自己的节奏翻页。', size: [190, 280] },
  folder: { title: '周末旅行', label: '文件夹', hint: '一个薄薄的文件袋。滚动查看全部示例，箭头进入子目录。', size: [231, 265] },
  web: { title: '田野手记 · 网页首屏', label: '网页', hint: '网页宽度适应纸面，在页面内部继续向下读。', size: [222, 268] },
  code: { title: 'LittleNote.swift', label: '代码', hint: '代码按纸面宽度换行，保留缩进和语法颜色。', size: [239, 272] },
  audio: { title: '午后的录音.m4a', label: '音频', hint: '录音以卡带展示；点击复制文件，右键打开。', size: [220, 165] },
  video: { title: '湖边的风.mov', label: '视频', hint: '视频以胶片展示；点击复制文件，右键打开。', size: [220, 195] },
  archive: { title: '旅行资料.zip', label: '压缩包', hint: '把零碎的参考收进一个带纸封条的小包裹。', size: [200, 200] },
  file: { title: '相机配置.dat', label: '其他文件', hint: '其他文件保留原位置，用一张轻薄的附件纸签表示。', size: [184, 225] },
  group: { title: '这次旅行的材料', label: '材料组', hint: '照片、文稿和链接放进同一个资料袋，随用随取。', size: [231, 265] }
};
const icons = {
  photo: '<span class="dock-photo"><img src="./assets/landscape.svg" alt=""></span>',
  note: '<span class="dock-note"></span>',
  document: '<span class="desktop-paper"><b>PDF</b><i></i><i></i><i></i></span>',
  folder: '<span class="desktop-folder"></span>',
  web: '<span class="dock-web"><svg viewBox="0 0 32 32"><circle cx="16" cy="16" r="13"/><ellipse cx="16" cy="16" rx="6" ry="13"/><path d="M3 16h26M6 8q10 5 20 0M6 24q10-5 20 0"/></svg></span>',
  code: '<span class="dock-code">&lt;/&gt;</span>',
  audio: '<svg viewBox="0 0 32 32"><rect x="3" y="7" width="26" height="18" rx="3"/><circle cx="10" cy="15" r="3"/><circle cx="22" cy="15" r="3"/><path d="M10 22h12"/></svg>',
  video: '<svg viewBox="0 0 32 32"><rect x="5" y="3" width="22" height="26" rx="1"/><path d="M9 3v26M23 3v26M5 9h4M5 16h4M5 23h4M23 9h4M23 16h4M23 23h4m-14-13 7 6-7 5Z"/></svg>',
  archive: '<svg viewBox="0 0 32 32"><path d="m4 10 12-5 12 5v16H4Zm0 0 12 5 12-5M16 15v11M10 8l12 5v6"/></svg>',
  word: '<svg viewBox="0 0 32 32"><path d="M8 3h13l5 5v21H8ZM20 3v6h6M12 14h10M12 18h10M12 22h7"/></svg>',
  file: '<svg viewBox="0 0 32 32"><path d="M7 3h13l6 6v20H7ZM19 3v7h7M12 17h9M12 21h9"/></svg>',
  group: '<svg viewBox="0 0 32 32"><path d="M4 11h24v16H4ZM6 11V7h9l3 4M9 7V4h10l3 4h4v3M7 22h18"/></svg>'
};
const escapeHTML = value => String(value).replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
let toastTimer, resizeTimer, hoverTimer, aimTarget, audioContext, oscillator, audioGain, audioOwner;

function toast(message, duration = 2900) {
  clearTimeout(toastTimer); const el = $('#toast'); el.textContent = message; el.classList.add('visible');
  toastTimer = setTimeout(() => el.classList.remove('visible'), duration);
}
function animateEnabled() { return state.motion && !reduced.matches; }
function localPoint(point) { return { x: point.x, y: point.y - 36 }; }
function setCapture(value) {
  if (!value) { gesture.cancel(); state.alt = false; }
  syncCapture();
}
function syncCapture() {
  state.capture = false;
  const on = gesture.active;
  document.body.classList.toggle('capture-on', on);
  $('#capture-toggle').setAttribute('aria-pressed', String(on));
  $('#cursor-clip').hidden = !on && !state.pickup;
  updateCursor();
}
function updateCursor() {
  const el = $('#cursor-clip'); el.style.transform = `translate(${state.point.x - 8}px,${state.point.y - 19}px)`;
}
function paperPage(kind, index) {
  const pages = kind === 'word' ? [
    ['周末出行计划', '目的地：海边的小镇\n日期：本周六', '09:30 出发\n11:00 沿海岸散步，记录风景\n14:00 找一家小店，写写手记\n17:00 趁夕阳回家'],
    ['随身物品', '相机 / 充电线 / 一本空白笔记', '把喜欢的片段夹在手边。'],
    ['行程记录', '示例文稿 · 第三页', '把喜欢的片段夹在手边。']
  ] : [
    ['旅行手记', 'A LITTLE JOURNEY / 2026', '山间的湖面，像一张留白的纸。\n停下来，记住这一刻。\n\n路线：林间小径 → 湖边 → 山谷\n随行：相机、笔记与好天气'],
    ['湖边', '翻页示例 / 02', '停下来，记住这一刻。'],
    ['山谷', '翻页示例 / 03', '随行：相机、笔记与好天气']
  ];
  const page=pages[index];
  return `<div class="paper-content native-document"><h2>${page[0]}</h2><p>${page[1]}</p>${kind==='document'?'<img src="./assets/landscape.svg" alt="山间湖泊">':''}<p>${page[2]}</p></div>`;
}
const ROOT_FILES = [
  ['灵感照片', true], ['阅读摘录', true], ['旅行手记.pdf', false, 'document'], ['出行计划.docx', false, 'word'],
  ['山间湖泊.png', false, 'photo'], ['LittleNote.swift', false, 'code'], ['Field Notes.webloc', false, 'web'],
  ['晨间笔记.txt', false, 'note'], ['午后的录音.m4a', false, 'audio'], ['湖边的风.mov', false, 'video'],
  ['旅行资料.zip', false, 'archive'], ['相机配置.dat', false, 'file'], ['图标参考', true], ['色彩记录.txt', false, 'note'], ['下一次出发.pdf', false, 'document']
];
function folderContent(obj) {
  const rows = obj.folder ? [['山间湖泊.png', false, 'photo'], ['旅行手记.pdf', false, 'document']] : (obj.entries || ROOT_FILES);
  const title = obj.folder || TYPES[obj.kind].title;
  return `<div class="folder-inner"><div class="folder-header">${obj.folder ? '<button data-folder-back aria-label="返回">‹</button>' : ''}<strong>${escapeHTML(title)}</strong><small>${rows.length} 项</small></div><div class="folder-list" tabindex="0">${rows.map(([name, folder, kind]) => `<div class="folder-row"><button class="entry-copy" draggable="true" data-copy-kind="${kind || 'folder'}" data-copy-name="${escapeHTML(name)}" title="复制 ${escapeHTML(name)}"><span class="${folder ? 'folder-tiny' : 'file-tiny'}"></span><span>${escapeHTML(name)}</span></button>${folder ? `<button class="arrow" data-folder="${escapeHTML(name)}" aria-label="进入 ${escapeHTML(name)}">›</button>` : ''}</div>`).join('')}</div></div>`;
}
function bodyHTML(obj) {
  switch (obj.kind) {
    case 'photo': return '<img class="photo-image" src="./assets/landscape.svg" alt="浅色远山、湖泊与松树的山间插画">';
    case 'note': return '<div class="native-note">周末的小计划<br><br>去海边走走，带上相机。<br>把喜欢的风景，夹在手边。<br><br>周六 09:30 · 晴</div>';
    case 'document': case 'word': return `<div class="document-page">${paperPage(obj.kind, obj.page)}<span class="paper-spine"></span></div><div class="page-navigation"><button data-page="-1" aria-label="上一页" ${obj.page === 0 ? 'disabled' : ''}>‹</button><span>${obj.page + 1} / 3</span><button data-page="1" aria-label="下一页" ${obj.page === 2 ? 'disabled' : ''}>›</button></div>`;
    case 'folder': return folderContent(obj);
    case 'group': return obj.selected ? `<button data-group-back>‹ 返回项目夹</button><div>${bodyHTML({kind:obj.selected,page:0})}</div>` : `<div class="group-rows">${['photo','document','note'].map(k=>`<div><button data-copy-kind="${k}" data-copy-name="${TYPES[k].title}">${icons[k]}<span>${TYPES[k].title}</span></button><button data-group-preview="${k}" aria-label="预览${TYPES[k].label}">›</button></div>`).join('')}</div>`;
    case 'web': return '<div class="web-scroll" tabindex="0" aria-label="田野手记网页"><div class="web-site native-web"><nav>FIELD NOTES / 田野手记</nav><main><small>周末阅读 · VOL. 08</small><h1>把日常的风景，<br>留在手边。</h1><p>一束光、一段文字、一个值得回来的页面。</p><section><article>山间漫步<p>给自己留一点空白。</p></article><article>纸上灵感<p>记录细小而珍贵的发现。</p></article></section></main></div></div>';
    case 'code': return '<div class="code-page"><pre><em>import</em> SwiftUI\n\n<em>struct</em> LittleNote: View {\n    <em>let</em> message = <b>"留住灵感"</b>\n\n    <em>var</em> body: some View {\n        Text(message)\n            .padding(<b>20</b>)\n    }\n}</pre></div>';
    case 'audio': return '<div class="media-content cassette"><div class="cassette-label">午后的录音.m4a<div class="reels"><i></i><i></i></div></div></div>';
    case 'video': return '<div class="media-content film"><img src="./assets/landscape.svg" alt="湖边的风.mov"></div>';
    case 'archive': return '<div class="archive"><strong>旅行资料.zip</strong></div>';
    case 'file': return '<div class="native-file"><span class="desktop-paper"><b>DAT</b></span><span>相机配置.dat</span></div>';
    default: return '';
  }
}
function contentActionHint(kind) {
  if (kind === 'folder' || kind === 'group') return '点条目复制 · 点箭头进入子目录';
  if (kind === 'web') return '滚动阅读 · 单击复制示例链接';
  if (kind === 'audio' || kind === 'video') return '单击复制文件 · 右键打开';
  return '单击复制示例 · 拖夹子移动 · 单击夹子收放';
}
function createObject(kind, options = {}) {
  const type = TYPES[kind]; if (!type) return null;
  if (state.objects.size >= 18) { const candidate = [...state.objects.values()].find(o => !o.initial); if (candidate) removeObject(candidate); else { toast('桌面有点满了，先收起几个夹项吧'); return null; } }
  const id = `clip-${++state.sequence}`, obj = { id, kind, page: 0, folder: null, turning: false, initial: false, x: 0, y: 0, width: type.size[0], height: type.size[1], ...options };
  const el = document.createElement('article'); el.id = id; el.className = `object object-${kind} ${obj.edge === 'right' ? 'side-right' : ''} ${obj.edge ? '' : 'floating'}`;
  el.dataset.initial = String(obj.initial);
  el.setAttribute('aria-label', `${type.title}，${contentActionHint(kind)}`);
  el.innerHTML = `<span class="nail"></span><div class="assembly"><button class="clip-grip" aria-label="拖动${type.label}，单击夹子收放" title="拖动移动 · 单击收放"><img src="./assets/clip-closed.webp" alt=""><img class="clip-open" src="./assets/clip-open.webp" alt=""></button><div class="compact-preview" aria-hidden="true">${kind === 'photo' ? '<img src="./assets/landscape.svg" alt="">' : icons[kind] || icons.document}</div><div class="object-body" tabindex="0" role="group" aria-label="${type.title}">${bodyHTML(obj)}</div><div class="object-tools"><button data-collapse title="收起" aria-label="收起${type.label}">−</button><button data-remove title="移除示例" aria-label="移除${type.label}">×</button></div><span class="object-label">${type.title}</span></div>`;
  obj.el = el; state.objects.set(id, obj); objects.append(el);
  applyObjectPosition(obj); bindObject(obj);
  if (options.enter !== false && animateEnabled()) { el.classList.add('revealing'); setTimeout(() => el.classList.remove('revealing'), HINGE.settle); }
  return obj;
}
function applyObjectPosition(obj) {
  const width = obj.width * (state.sizes[obj.kind] || 100) / 100;
  obj.el.style.setProperty('--x', `${obj.x}px`); obj.el.style.setProperty('--y', `${obj.y}px`);
  obj.el.style.setProperty('--w', `${width}px`); obj.el.style.setProperty('--object-scale', 1);
  obj.el.style.setProperty('--closed-angle', `${hingeAngle(0, obj.edge === 'right' ? 'right' : 'left')}deg`);
}
function removeObject(obj) {
  if (audioOwner === obj.id) stopAudio();
  if (state.drag?.obj === obj) endDrag(true);
  state.objects.delete(obj.id); obj.el.remove();
}
function toggleObject(obj, expanded, temporary = false) {
  const collapse = expanded === undefined ? !obj.el.classList.contains('collapsed') : !expanded;
  if (collapse && !obj.edge) {
    obj.edge = obj.x + obj.width/2 < innerWidth/2 ? 'left' : 'right';
  }
  if (obj.edge) {
    const width = obj.width * (state.sizes[obj.kind] || 100)/100;
    obj.x = obj.edge === 'left' ? 0 : innerWidth - (collapse ? 64 : width);
    obj.el.classList.toggle('side-right',obj.edge==='right'); obj.el.classList.remove('floating');
  }
  obj.sticky = !collapse && !temporary;
  obj.el.classList.toggle('collapsed', collapse);
  $('.clip-grip', obj.el).setAttribute('aria-expanded', String(!collapse));
  applyObjectPosition(obj);
  if (!collapse) {
    obj.el.style.zIndex = ++state.z;
    if(animateEnabled()) {obj.el.classList.add('revealing');setTimeout(()=>obj.el.classList.remove('revealing'),800);}
  }
}
function bindObject(obj) {
  const el = obj.el, grip = $('.clip-grip', el), body = $('.object-body', el);
  body.draggable = true;
  body.addEventListener('dragstart', event => {
    if (gesture.active || state.pickup || el.classList.contains('collapsed') || (event.target.closest('button') && !event.target.closest('[data-copy-kind]'))) { event.preventDefault(); return; }
    cancelTour(false); clearAim();
    event.dataTransfer.effectAllowed = 'copy';
    event.dataTransfer.setData('application/x-clamp-demo', obj.id);
    const row=event.target.closest('[data-copy-kind]');
    if(row) event.dataTransfer.setData('application/x-clamp-entry',JSON.stringify({kind:row.dataset.copyKind,title:row.dataset.copyName}));
    event.dataTransfer.setData('text/plain', row ? row.dataset.copyName : ['note','code'].includes(obj.kind) ? body.innerText.trim() : TYPES[obj.kind].title);
    if (obj.kind === 'photo') event.dataTransfer.setData('text/uri-list', asset('landscape.svg'));
    document.body.classList.add('exporting');
    toast('拖到右上角的「周末旅行」，试试复制交接 · 原夹项会保留', 3700);
  });
  body.addEventListener('dragend', () => { obj.suppressClickUntil=performance.now()+250; document.body.classList.remove('exporting'); });
  if (obj.kind === 'folder') bindCopyDestination(body, obj);
  grip.setAttribute('aria-expanded', 'true');
  grip.addEventListener('pointerdown', event => startDrag(obj, event));
  grip.addEventListener('click', event => { if (event.detail === 0) toggleObject(obj); });
  $('[data-collapse]', el).addEventListener('click', () => toggleObject(obj, false));
  $('[data-remove]', el).addEventListener('click', () => removeObject(obj));
  body.addEventListener('click', event => {
    if (performance.now() < (obj.suppressClickUntil || 0)) return;
    if (event.target.closest('button,a') || state.pickup || event.defaultPrevented) return;
    if (el.classList.contains('collapsed')) { toggleObject(obj, true); return; }
    if (gesture.active) return;
    copyObject(obj);
  });
  body.addEventListener('keydown', event => { if ((event.key === 'Enter' || event.key === ' ') && event.target === body) { event.preventDefault(); copyObject(obj); } });
  el.addEventListener('pointerenter', () => {
    clearTimeout(hoverTimer);
    if (!state.drag && obj.edge && el.classList.contains('collapsed') && !(gesture.active)) {
      clearTimeout(hoverTimer); hoverTimer = setTimeout(() => toggleObject(obj, true, true), 350);
    }
  });
  el.addEventListener('pointerleave', () => { clearTimeout(hoverTimer); if(obj.edge && !obj.sticky && !state.drag) hoverTimer=setTimeout(()=>toggleObject(obj,false),450); });
  body.addEventListener('pointerdown', event => {
    if (event.target.closest('button,a')) return;
    if (gesture.active) { obj.suppressClickUntil=performance.now()+1000; beginPickup(obj.kind, body, event); }
  });
  body.addEventListener('wheel', event => {
    if (!['document', 'word'].includes(obj.kind) || state.drag || state.pickup) return;
    event.preventDefault();
    const now=performance.now();
    if(now-(obj.lastWheelEvent || -Infinity)>300){obj.wheelConsumed=false;obj.wheel=0;}
    obj.lastWheelEvent=now;
    if(obj.wheelConsumed || now-(obj.lastWheel || -Infinity)<500) return;
    const delta=Math.abs(event.deltaY)>=Math.abs(event.deltaX)?event.deltaY:event.deltaX;
    obj.wheel=(obj.wheel || 0)+delta;
    if(Math.abs(obj.wheel)<(event.deltaMode===0?24:1)) return;
    const step=Math.sign(obj.wheel);obj.wheel=0;obj.wheelConsumed=true;obj.lastWheel=now;turnPage(obj,step);
  }, { passive: false });
  el.addEventListener('click', event => {
    const preview=event.target.closest('[data-group-preview]'); if(preview){obj.selected=preview.dataset.groupPreview;refreshBody(obj);}
    if(event.target.closest('[data-group-back]')){obj.selected=null;refreshBody(obj);}
    const page = event.target.closest('[data-page]'); if (page) turnPage(obj, Number(page.dataset.page));
    const folder = event.target.closest('[data-folder]'); if (folder) { obj.folder = folder.dataset.folder; refreshBody(obj); }
    if (event.target.closest('[data-folder-back]')) { obj.folder = null; refreshBody(obj); }
    const entry = event.target.closest('[data-copy-kind]'); if (entry) copyObject({kind: entry.dataset.copyKind, title: entry.dataset.copyName, el: obj.el});
  });
}
function bindCopyDestination(element, folder) {
  element.addEventListener('dragover', event => {
    if (!event.dataTransfer.types.includes('application/x-clamp-demo')) return;
    event.preventDefault(); event.dataTransfer.dropEffect = 'copy'; element.classList.add('copy-destination');
  });
  element.addEventListener('dragleave', event => { if (!element.contains(event.relatedTarget)) element.classList.remove('copy-destination'); });
  element.addEventListener('drop', event => {
    event.preventDefault(); element.classList.remove('copy-destination'); document.body.classList.remove('exporting');
    const original = state.objects.get(event.dataTransfer.getData('application/x-clamp-demo')); if (!original) return;
    let target = folder || [...state.objects.values()].find(obj => obj.kind === 'folder' && obj.initial);
    if (!target || getComputedStyle(target.el).display === 'none') target = createObject('folder', { x: innerWidth / 2 - 110, y: 110, width: 220 });
    if (!target) return;
    target.entries ||= ROOT_FILES.map(row => [...row]);
    let payload={kind:original.kind,title:TYPES[original.kind].title};
    try { const entry=JSON.parse(event.dataTransfer.getData('application/x-clamp-entry')); if(entry && TYPES[entry.kind] && typeof entry.title==='string') payload=entry; } catch {}
    target.entries.unshift([payload.title, payload.kind==='folder', payload.kind]); target.folder = null;
    refreshBody(target); toggleObject(target, true); target.el.style.zIndex = ++state.z;
    toast('✓ 已复制到示例文件袋 · 原夹项继续留在桌面上');
  });
}
function refreshBody(obj) { $('.object-body', obj.el).innerHTML = bodyHTML(obj); }
function turnPage(obj, step) {
  if (obj.turning || obj.el.classList.contains('collapsed')) return;
  const next = clamp(obj.page + step, 0, 2); if (next === obj.page) return;
  const page = $('.document-page', obj.el), old = $('.paper-content', page);
  obj.page = next; obj.turning = true;
  if (!animateEnabled()) { refreshBody(obj); obj.turning = false; return; }
  page.insertAdjacentHTML('afterbegin', paperPage(obj.kind, next));
  const newPage = $('.paper-content', page); newPage.classList.add('document-under');
  if (step > 0) old.classList.add('turning-page');
  else { old.remove(); newPage.classList.remove('document-under'); newPage.classList.add('turning-page', 'backward'); }
  setTimeout(() => { if (!state.objects.has(obj.id)) return; obj.turning = false; refreshBody(obj); }, 540);
}
async function copyObject(obj) {
  const title = obj.title || TYPES[obj.kind].title;
  // A file payload stays a file in the simulated desktop clipboard.
  // Browsers cannot put Finder file URLs on the system clipboard.
  state.clipboard = { kind: obj.kind, title };
  const body = $('.object-body', obj.el);
  if (['note', 'code'].includes(obj.kind)) {
    try { await navigator.clipboard?.writeText(body.innerText); } catch {}
  }
  $('.copy-feedback', body)?.remove();
  const feedback = document.createElement('span'); feedback.className = 'copy-feedback'; feedback.textContent = '✓ 已复制'; body.append(feedback);
  setTimeout(() => feedback.remove(), 1100);
  $('#clipboard-status').textContent = `桌面演示剪贴板：${title} · 可在示例访达中 ⌘V 粘贴`;
}
function startDrag(obj, event) {
  if (event.button !== 0 || state.pickup) return;
  event.preventDefault(); event.stopPropagation(); cancelTour(false); clearTimeout(hoverTimer);
  const expanded = !obj.el.classList.contains('collapsed');
  // A compact clip remains compact while pressed; dragging never hover-expands it.
  state.drag = { obj, pointer: event.pointerId, element: event.currentTarget, start: { x: event.clientX, y: event.clientY }, x: obj.x, y: obj.y, moved: false, last: { x: event.clientX, y: event.clientY, t: performance.now() }, vx: 0, vy: 0, expanded };
  event.currentTarget.setPointerCapture(event.pointerId); obj.el.style.zIndex = ++state.z;
}
function moveDrag(event) {
  const d = state.drag; if (!d || event.pointerId !== d.pointer) return;
  const dx = event.clientX - d.start.x, dy = event.clientY - d.start.y;
  if (!d.moved && Math.hypot(dx, dy) <= 4) return;
  d.moved = true; clearTimeout(hoverTimer); d.obj.el.classList.add('is-dragging');
  const now = performance.now(), dt = Math.max(8, now - d.last.t);
  d.vx = (event.clientX - d.last.x) / dt; d.vy = (event.clientY - d.last.y) / dt; d.last = { x: event.clientX, y: event.clientY, t: now };
  const o = d.obj, width = o.width * (state.sizes[o.kind] || 100) / 100;
  o.x = clamp(d.x + dx, -width * .25, innerWidth - width * .75); o.y = clamp(d.y + dy, 20, innerHeight - 200);
  o.el.style.setProperty('--tilt', `${clamp(d.vx * (3 + MATERIALS[o.kind].inertia * 4), -9, 9)}deg`);
  applyObjectPosition(o);
}
function endDrag(cancelled = false) {
  const d = state.drag; if (!d) return; state.drag = null;
  if (d.element.hasPointerCapture(d.pointer)) d.element.releasePointerCapture(d.pointer);
  const o = d.obj; o.el.classList.remove('is-dragging');
  if (cancelled) { o.x = d.x; o.y = d.y; applyObjectPosition(o); return; }
  if (!d.moved) { toggleObject(o, d.expanded ? false : true); return; }
  o.el.classList.remove('collapsed');
  const width = o.width * (state.sizes[o.kind] || 100) / 100;
  o.edge = d.last.x < 42 ? 'left' : d.last.x > innerWidth - 42 ? 'right' : null;
  if (o.edge) o.x = o.edge === 'left' ? 14 : innerWidth - width - 14;
  o.el.classList.toggle('side-right', o.edge === 'right'); o.el.classList.toggle('floating', !o.edge);
  o.el.style.setProperty('--tilt', '0deg'); applyObjectPosition(o);
  if (o.edge) { toggleObject(o, false); toast('已夹在边缘 · 悬停片刻或单击夹子展开'); }
  else { o.el.classList.add('settling'); setTimeout(() => o.el.classList.remove('settling'), 660); }
}
function openWorkbench() {
  const bench = $('#workbench'); bench.hidden = false; document.body.classList.add('workbench-open');
  bench.innerHTML = `<div class="window-titlebar"><button class="traffic" data-close-workbench aria-label="关闭访达"></button><span class="traffic"></span><span class="traffic"></span><strong>周末旅行</strong></div><div class="window-content"><div class="source-grid"><div class="source-item" data-kind="photo"><img src="./assets/landscape.svg" alt="山间湖泊"></div><div class="source-item source-text" data-kind="note"><p>周末的小计划<br><br>去海边走走，带上相机。<br>把喜欢的风景，夹在手边。<br><br>周六 09:30 · 晴</p></div></div><div class="finder-files">${Object.entries(TYPES).filter(([k]) => !['photo','note','group'].includes(k)).map(([k,t])=>`<div class="source-item finder-file" data-kind="${k}" tabindex="0">${icons[k]}<span>${t.title}</span></div>`).join('')}</div><div id="pasted-files"></div><p class="window-hint">按住 ⌥ Option → 按下对象 → 保持 Option 并拖动 → 松开鼠标放置。<br>提前松开 Option、Esc 或右键取消。浏览器中的文件交接使用示例剪贴板。</p></div>`;
  $('[data-close-workbench]', bench).addEventListener('click', closeWorkbench);
  $$('.source-item', bench).forEach(source => {
    source.addEventListener('pointerdown', event => { if (gesture.active && event.button === 0) beginPickup(source.dataset.kind, source, event); });
    source.addEventListener('pointerenter', () => { if (gesture.active) aim(source); });
    source.addEventListener('pointerleave', clearAim);
    source.addEventListener('pointermove',()=>{if(gesture.active && !state.pickup) aim(source);});
  });
  bindWindowDrag($('.window-titlebar', bench), bench);
}
function closeWorkbench() {
  cancelTour(false); cancelPickup(); $('#workbench').hidden = true; document.body.classList.remove('workbench-open'); clearAim();
  if (state.capture) setCapture(false, false);
}
function bindWindowDrag(handle, el) {
  let drag;
  handle.addEventListener('pointerdown', event => {
    if (event.target.closest('button') || event.button !== 0) return;
    const r = el.getBoundingClientRect(); drag = { x: event.clientX, y: event.clientY, left: r.left, top: r.top - 36 };
    handle.setPointerCapture(event.pointerId);
  });
  handle.addEventListener('pointermove', event => {
    if (!drag) return;
    el.style.left = `${clamp(drag.left + event.clientX - drag.x, 5, Math.max(5, innerWidth - el.offsetWidth - 5))}px`;
    el.style.top = `${clamp(drag.top + event.clientY - drag.y, 10, Math.max(10, innerHeight - el.offsetHeight - 160))}px`;
    el.style.transform = 'none';
  });
  const done = () => { drag = null; }; handle.addEventListener('pointerup', done); handle.addEventListener('pointercancel', done); handle.addEventListener('lostpointercapture', done);
}
let aimTimer;
function clearAim() {
  clearTimeout(aimTimer); if (aimTarget) { aimTarget.classList.remove('aiming'); $('.subject-aim', aimTarget)?.remove(); aimTarget = null; }
}
function aim(target) {
  clearAim(); if (!gesture.active) return;
  aimTarget = target;
  aimTimer = setTimeout(() => { if (gesture.active && aimTarget === target) target.classList.add('aiming'); }, 300);
}
function beginPickup(kind, source, event) {
  if (!gesture.press() || state.pickup || state.drag) return;
  event.preventDefault(); event.stopPropagation(); cancelTour(false);
  state.point = { x: event.clientX, y: event.clientY }; updateCursor();
  animatePickup(kind, source, { pointer: event.pointerId, start: { ...state.point } });
}
function animatePickup(kind, source, pointer = null) {
  if (state.pickup) return;
  const r = source.getBoundingClientRect(), initial = { x: r.x, y: r.y, width: r.width, height: r.height };
  const copy = document.createElement('div'); copy.className = 'flight-object';
  const isPhoto = kind === 'photo';
  copy.innerHTML = isPhoto ? '<img src="./assets/landscape.svg" alt="">' : `<span class="mini-text">${escapeHTML(TYPES[kind].title)}</span>`;
  $('#flight-layer').append(copy);
  const duration = animateEnabled() ? 440 + MATERIALS[kind].inertia * 160 : 0;
  const pickup = { kind, source, initial, copy, pointer, start: performance.now(), duration, held: false, released: false, frame: null };
  state.pickup = pickup;
  if (!pointer) state.point = { x: r.right + 10, y: r.top + 15 };
  $('#cursor-clip').hidden = false; updateCursor(); clearAim(); source.classList.add('aiming');
  const tick = now => {
    if (state.pickup !== pickup) return;
    const p = duration ? clamp((now - pickup.start) / duration) : 1;
    const sample = pickupSample(p, initial, state.point, kind);
    Object.assign(copy.style, { left: `${sample.x}px`, top: `${sample.y}px`, width: `${sample.width}px`, height: `${sample.height}px`, transform: `rotate(${sample.angle}deg) scaleY(${1 - sample.compression})`, borderRadius: `${sample.bend * .3}px` });
    $('#cursor-clip>img').src = asset(sample.jaw > .4 ? 'cursor-open.webp' : 'cursor-closed.webp');
    if (p < 1) pickup.frame = requestAnimationFrame(tick);
    else {
      pickup.held = true; copy.remove(); source.classList.remove('aiming');
      const cursor = $('#cursor-clip'); cursor.classList.add('holding');
      $('.carried', cursor).innerHTML = isPhoto ? '<img src="./assets/landscape.svg" alt="">' : '';
      if (!pointer || pickup.released) finishPickup();
    }
  };
  pickup.frame = requestAnimationFrame(tick);
}
function finishPickup() {
  const p = state.pickup; if (!p) return;
  if (!p.held) { p.released = true; return; }
  const position = localPoint(state.point), mobile = innerWidth <= 600;
  const target = p.destination || position;
  const size = TYPES[p.kind].size;
  const object = createObject(p.kind, { ...placement(target, { width: innerWidth, height: innerHeight }, { width: size[0], height: size[1] }), width: mobile ? size[0] * .72 : size[0] });
  if (object?.edge) toggleObject(object, false);
  gesture.cancel();
  p.copy.remove(); p.source.classList.remove('aiming'); state.pickup = null;
  $('#cursor-clip').classList.remove('holding'); $('#cursor-clip>img').src = asset('cursor-open.webp'); syncCapture();
  if (object) toast('✓ 已夹住', 1200);
}
function cancelPickup() {
  const p = state.pickup; if (!p) return;
  cancelAnimationFrame(p.frame); p.copy.remove(); p.source?.classList.remove('aiming'); state.pickup = null;
  $('#cursor-clip').classList.remove('holding'); $('#cursor-clip>img').src = asset('cursor-open.webp'); syncCapture();
}
function addExample(kind) {
  if (!TYPES[kind]) return; cancelTour(false);
  const mobile = innerWidth <= 600, size = TYPES[kind].size;
  const width = mobile ? size[0] * .78 : size[0];
  const index = state.sequence % 4;
  const object = createObject(kind, { x: mobile ? 18 + index * 21 : innerWidth / 2 - width / 2 + (index - 1.5) * 42,
    y: mobile ? innerHeight * .48 + (index % 2) * 18 : 95 + index * 28, width });
  if (object) { object.el.style.zIndex = ++state.z; toast(TYPES[kind].hint, 3300); }
}
function stopAudio() {
  try { oscillator?.stop(); } catch {}
  oscillator = null; audioGain = null;
  if (audioOwner) { const o = state.objects.get(audioOwner); if (o) { $('.cassette', o.el)?.classList.remove('playing'); const b = $('[data-play]', o.el); if (b) b.textContent = '▶ 点击听一段合成音'; } }
  audioOwner = null;
}
function showDialog(title, body) {
  cancelTour(false); clearAim(); if (dialog.open) dialog.close();
  $('#dialog-content').innerHTML = `<div class="dialog-head"><h2 id="dialog-title">${title}</h2><button class="dialog-close" aria-label="关闭窗口">×</button></div><div class="dialog-body">${body}</div>`;
  $('.dialog-close', dialog).addEventListener('click', () => dialog.close()); dialog.showModal();
}
function showAbout() {
  showDialog('关于屏幕夹子', `<div class="about-mark"><img src="./assets/app-icon.webp" alt="屏幕夹子图标"><div><strong>屏幕夹子</strong><small>ClampEverything · a little closer.</small></div></div><p>把常用的照片、文字、文稿、网页和文件夹夹在屏幕边缘。需要时翻出来，参考时留在眼前，交接时拖向其他应用。</p><div class="about-facts"><span>macOS 原生</span><span>Apple Silicon</span><span>开源免费</span><span>本地资料库</span></div><a class="download-button about-download" href="https://github.com/Quartzsyr/ClampEverything/releases/latest">下载最新公开版 ↗</a><p class="release-note">本页是浏览器内的交互演示，按本地桌面端代码还原主要夹取交互。下载版本、安装包和实际功能以 <a href="https://github.com/Quartzsyr/ClampEverything/releases/latest" target="_blank" rel="noopener">GitHub Release</a> 为准。当前公开版为 v1.6.4，macOS 14+，开发签名，尚未公证。</p><p class="release-note">参考 <a href="https://tendedero.app" target="_blank" rel="noopener">Tendedero</a> 用桌面演示产品的表达方式；本页复用屏幕夹子的夹子与纸张素材，山景按原生引导示例重建。<a href="https://github.com/Quartzsyr/ClampEverything" target="_blank" rel="noopener">查看源码 ↗</a></p>`);
}
function showHelp() {
  showDialog('鼠标夹取', `<ol class="help-steps"><li>先打开示例访达，按住 ⌥ Option，鼠标变成张开的夹子。</li><li>按下对象，继续按住 Option 和鼠标，拖到需要的位置。</li><li>松开鼠标放置。距离左右边缘 42 点内吸附；提前松开 Option、Esc、右键均取消。</li><li>拖金属夹移动位置；点金属夹收起。边缘悬停 350 毫秒展开，离开 450 毫秒收起；点开后保持展开。</li><li>点击内容复制；拖内容向外复制。文件夹点条目复制、点箭头进入；PDF 与文稿滚轮翻页。</li></ol><p>网页中的系统文件、访达、剪贴板和打开应用使用内置示例模拟，无法访问你的 Mac 文件。主体识别未在网页中实现，不展示假识别结果。真实系统操作请使用 Mac 版。</p>`);
}
function showMaterials() {
  showDialog('万物，皆可夹取', `<p>选一件放到桌面上。每种内容都有自己的质感和重量。</p><div class="material-grid">${Object.entries(TYPES).map(([kind, type]) => `<button data-material="${kind}">${icons[kind]}<span>${type.label}</span><small>${kind === 'document' || kind === 'word' ? '左侧装订 · 向外翻页' : kind === 'audio' ? '挺括卡带 · 轻摆' : kind === 'folder' ? '薄纸文件袋 · 可浏览' : '夹点翻转 · 松手回摆'}</small></button>`).join('')}</div>`);
  $$('[data-material]', dialog).forEach(button => button.addEventListener('click', () => { dialog.close(); addExample(button.dataset.material); }));
}
function showSettings() {
  showDialog('让桌面，顺你的手', `<div class="setting-row"><label for="motion-setting">拟物动效<small>翻转、夹取过渡与纸张回摆；尊重系统减少动态效果</small></label><input id="motion-setting" type="checkbox" ${state.motion ? 'checked' : ''}></div><div class="setting-row"><label for="brass-setting">显示黄铜接收夹<small>右上角的添加入口，默认关闭</small></label><input id="brass-setting" type="checkbox" ${state.brass ? 'checked' : ''}></div><h3>按内容调整大小</h3>${Object.keys(TYPES).map(kind => `<div class="setting-row"><label for="size-${kind}">${TYPES[kind].label}</label><input id="size-${kind}" data-size="${kind}" type="range" min="65" max="180" step="5" value="${state.sizes[kind] || 100}"><output for="size-${kind}">${state.sizes[kind] || 100}%</output></div>`).join('')}<section class="developer-info" aria-labelledby="developer-title"><h3 id="developer-title">开发者信息</h3><strong>Quartz</strong><p>UESTC</p><a href="mailto:SYRQuartz@gmail.com">SYRQuartz@gmail.com</a></section><p class="release-note">这些设置只影响此网页的示例，会保存在当前浏览器。Mac 应用的设置独立保存。</p>`);
  $('#motion-setting').addEventListener('change', event => { state.motion = event.target.checked; document.body.classList.toggle('motion-off', !state.motion); savePreferences(); });
  $('#brass-setting').addEventListener('change', event => { state.brass = event.target.checked; $('#receiver').hidden = !state.brass; savePreferences(); });
  $$('[data-size]', dialog).forEach(input => input.addEventListener('input', () => { const kind = input.dataset.size; state.sizes[kind] = Number(input.value); input.nextElementSibling.value = `${input.value}%`; state.objects.forEach(obj => { if (obj.kind === kind) applyObjectPosition(obj); }); savePreferences(); }));
}
function savePreferences() {
  try { localStorage.setItem('clamp-desktop-v1', JSON.stringify({ sizes: state.sizes, motion: state.motion, theme: state.theme, brass: state.brass })); } catch {}
}
function loadPreferences() {
  try {
    const p = JSON.parse(localStorage.getItem('clamp-desktop-v1') || '{}');
    state.motion = typeof p.motion === 'boolean' ? p.motion : !reduced.matches; state.theme = p.theme === 'night' ? 'night' : 'day'; state.brass = p.brass === true;
    for (const kind of Object.keys(TYPES)) if (Number.isFinite(p.sizes?.[kind])) state.sizes[kind] = clamp(p.sizes[kind], 75, 135);
  } catch {}
  document.body.classList.toggle('night', state.theme === 'night'); document.body.classList.toggle('motion-off', !state.motion); $('#receiver').hidden = !state.brass;
}
function toggleTheme() { state.theme = state.theme === 'night' ? 'day' : 'night'; document.body.classList.toggle('night', state.theme === 'night'); savePreferences(); }
function layoutInitial(reset = false) {
  const width = innerWidth, height = innerHeight, mobile = width <= 600;
  const specs = mobile ? [
    ['photo', 15, Math.max(height * .55, 360), 137, 'left', false],
    ['note', width - 144, Math.max(height * .54, 350), 132, 'right', false],
    ['document', width - 115, 130, 145, 'right', true],
    ['folder', -90, 115, 150, 'left', true]
  ] : [
    ['photo', width < 1000 ? 24 : width * .055, height * .20, clamp(width * .17, 154, 247), 'left', false],
    ['note', width - clamp(width * .15, 160, 217) - (width < 1050 ? 19 : width * .05), height * .43, clamp(width * .15, 160, 217), 'right', false],
    ['document', width - clamp(width * .125, 146, 186) - (width < 1050 ? 111 : width * .145), 64, clamp(width * .125, 146, 186), 'right', false],
    ['folder', width < 1000 ? 27 : width * .075, height * .55, clamp(width * .155, 155, 220), 'left', false]
  ];
  for (const [index, [kind, x, y, w, edge, collapsed]] of specs.entries()) {
    let o = [...state.objects.values()].find(o => o.initial && o.kind === kind);
    if (!o && reset) o = createObject(kind, { x, y, width: w, edge, initial: true, enter: false });
    if (!o) continue;
    o.x = x; o.y = Math.min(y, height - (kind === 'folder' ? 310 : 265)); o.width = w; o.edge = edge;
    applyObjectPosition(o); toggleObject(o, !collapsed);
    if (reset && animateEnabled()) { o.el.classList.add('revealing'); o.el.style.animationDelay = `${index * .12}s`; $('.assembly', o.el).style.animationDelay = `${index * .12}s`; setTimeout(() => o.el.classList.remove('revealing'), 1200); }
  }
}
function resetDesktop(announce = true) {
  cancelTour(false); cancelPickup(); endDrag(true); stopAudio(); clearAim();
  for (const o of [...state.objects.values()]) removeObject(o);
  state.sequence = 0; state.alt = false; setCapture(false, false); $('#workbench').hidden = true; $('#workbench').removeAttribute('style'); document.body.classList.remove('workbench-open');
  layoutInitial(true); if (announce) toast('桌面已整理好，继续随手试试');
}
const pause = ms => new Promise(resolve => setTimeout(resolve, ms));
function cancelTour(announce = true) { if (state.tour) { state.tour = 0; if (announce) toast('演示已暂停，桌面交给你'); } }
async function runTour() {
  if (state.tour) { cancelTour(); return; }
  openWorkbench();
  toast('请按住 ⌥ Option，在访达的照片上按下并拖动；松开鼠标放置。',6000);
}
function initDock() {
  $('#dock').innerHTML = `<button class="dock-button" data-action="capture" aria-label="打开示例访达"><span class="desktop-folder"></span><span class="dock-label">访达 · 示例文件</span></button><button class="dock-button" data-action="settings" aria-label="屏幕夹子设置"><img src="./assets/app-icon.webp" alt=""><span class="dock-label">屏幕夹子</span></button>`;
}
const actions = { about: showAbout, help: showHelp, settings: showSettings, add: showMaterials, theme: toggleTheme,
  tour: runTour, capture: () => { cancelTour(false); openWorkbench(); }, reset: () => resetDesktop() };
document.addEventListener('click', event => { const button = event.target.closest('[data-action]'); if (button) actions[button.dataset.action]?.(); });
$$('[data-open]').forEach(button => { button.addEventListener('dblclick', openWorkbench); button.addEventListener('pointerdown', e => { if (gesture.active && e.button === 0) beginPickup(button.dataset.open, button, e); }); });
bindCopyDestination($('.desktop-files [data-open="folder"]'));
document.addEventListener('pointermove', event => {
  state.point = { x: event.clientX, y: event.clientY };
  if (gesture.active || state.pickup) updateCursor(); moveDrag(event);
}, { passive: true });
document.addEventListener('pointerup', event => { if (state.drag?.pointer === event.pointerId) endDrag(); if (state.pickup?.pointer?.pointer === event.pointerId && gesture.release()) { state.pickup.destination = localPoint({x:event.clientX,y:event.clientY}); finishPickup(); } });
document.addEventListener('pointercancel', () => { endDrag(true); cancelPickup(); });
document.addEventListener('contextmenu', event => {
  if (gesture.active || state.pickup) { event.preventDefault(); gesture.cancel(); cancelPickup(); clearAim(); syncCapture(); return; }
  const object = event.target.closest('.object'); if (!object) return;
  event.preventDefault(); const obj = state.objects.get(object.id);
  showDialog(TYPES[obj.kind].title, '<button id="context-copy">复制</button><button id="context-open">打开</button><button id="context-preview">快速查看</button><button id="context-finder">在访达中显示</button>');
  $('#context-copy').onclick=()=>{dialog.close();copyObject(obj)};
  $('#context-open').onclick=()=>{ if(obj.kind==='folder'){dialog.close();openWorkbench();}else{showDialog(TYPES[obj.kind].title,`<p class="release-note">系统打开操作的网页预览。Mac 版会交给关联应用打开原文件。</p><div class="quick-preview">${bodyHTML(obj)}</div>`);} };
  $('#context-preview').onclick=()=>showDialog(TYPES[obj.kind].title, `<div class="quick-preview">${bodyHTML(obj)}</div>`);
  $('#context-finder').onclick=()=>{dialog.close();openWorkbench()};
});
document.addEventListener('keydown', event => {
  if (event.key === 'Escape') { gesture.cancel(); cancelTour(); cancelPickup(); endDrag(true); clearAim(); syncCapture(); return; }
  if (dialog.open || event.target.matches('input,textarea')) return;
  if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === 'v' && state.clipboard && !$('#workbench').hidden) {
    event.preventDefault(); const row=document.createElement('p'); row.textContent=state.clipboard.title; $('#pasted-files').append(row); return;
  }
  if (event.key === 'Alt' && !event.repeat && !event.metaKey && !event.ctrlKey && !event.shiftKey) {
    state.alt=true; gesture.hold(); syncCapture(); const target=document.elementFromPoint(state.point.x,state.point.y)?.closest('.source-item'); if(target) aim(target);
  } else if (gesture.active && event.key !== 'Alt') { gesture.cancel(); cancelPickup(); clearAim(); syncCapture(); }
});
document.addEventListener('keyup', event => { if (event.key === 'Alt') { state.alt=false; gesture.unhold(); if (state.pickup && !state.pickup.released) cancelPickup(); clearAim(); syncCapture(); } });
window.addEventListener('blur', () => { gesture.unhold(); state.alt = false; endDrag(true); cancelPickup(); clearAim(); syncCapture(); });
document.addEventListener('visibilitychange', () => { if (document.hidden) { cancelTour(false); cancelPickup(); stopAudio(); } });
window.addEventListener('resize', () => { clearTimeout(resizeTimer); resizeTimer = setTimeout(() => { cancelPickup(); endDrag(true); layoutInitial(); for (const o of state.objects.values()) if (!o.initial) { o.x = clamp(o.x, 8, Math.max(8, innerWidth - o.width * (state.sizes[o.kind] || 100) / 100 - 8)); o.y = clamp(o.y, 50, Math.max(50, innerHeight - 300)); applyObjectPosition(o); } }, 120); });
dialog.addEventListener('click', event => { if (event.target === dialog) { const r = dialog.getBoundingClientRect(); if (event.clientX < r.left || event.clientX > r.right || event.clientY < r.top || event.clientY > r.bottom) dialog.close(); } });
function updateClock() { $('#clock').textContent = new Intl.DateTimeFormat('zh-CN', { month: 'numeric', day: 'numeric', weekday: 'short', hour: '2-digit', minute: '2-digit', hour12: false }).format(new Date()); $('#clock').dateTime = new Date().toISOString(); }
loadPreferences(); initDock(); layoutInitial(true); updateClock(); setInterval(updateClock, 30000);
reduced.addEventListener('change', () => { if (reduced.matches) { cancelPickup(); stopAudio(); } });
