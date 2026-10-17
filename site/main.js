import { createFeedback } from './assets/feedback.js';
import { createWallpapers, WALLPAPERS } from './assets/wallpapers.js';
import { bindSystemMenu } from './assets/system-menu.js';
import { createDesktop } from './desktop.js?v=20261017-onboarding';
import { HINGE, MATERIALS, clamp, pickupSample } from './motion.js';
import { FileLibrary } from './file-library.js?v=20261016-dock';
import { HoldGesture } from './hold-gesture.js';

const $ = (s, root = document) => root.querySelector(s);
const $$ = (s, root = document) => [...root.querySelectorAll(s)];
const reduced = matchMedia('(prefers-reduced-motion: reduce)');
const nativeBase = new URL('./assets/native/', import.meta.url);
const nativeURL = path => {const url=new URL(path,nativeBase);if(['http:','https:'].includes(url.protocol))url.searchParams.set('v','20261017-onboarding');return url.href;};
const dialog = $('#info-dialog');
const objects = new Map();
const gesture = new HoldGesture();
const files = new FileLibrary(nativeURL);
const labels = {photo:'照片',note:'便笺',document:'PDF',word:'Word',folder:'文件夹',web:'网页',code:'代码',audio:'音频',video:'视频',archive:'压缩包',file:'其他文件',group:'收纳夹'};
let manifest, environment, sequence=0, run=0, z=5, dragging=null, manual=null;
let motion = !reduced.matches;
let statusTimer;
let hasPointer = false;
const cursor = $('#demo-cursor');
const point = {x:0,y:0};
const animated = () => motion && !reduced.matches;
const feedback=createFeedback({animated});
const wallpapers=createWallpapers({animated,busy:()=>!!manual||!!dragging||!!document.querySelector('.interacting,[data-window-motion]')});
const escapeHTML = value => String(value).replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const pause = ms => new Promise(resolve=>setTimeout(resolve, animated()?ms:Math.min(ms,100)));
const status = (title,detail='',options={}) => {
  clearTimeout(statusTimer);const element=$('#demo-status');element.dataset.tone=options.kind||'';
  element.innerHTML=`<span class="status-copy"><b>${escapeHTML(title)}</b>${detail?`<small>${escapeHTML(detail)}</small>`:''}</span>${options.action?`<button type="button">${escapeHTML(options.action.label)}</button>`:''}`;
  element.classList.toggle('has-action',!!options.action);element.classList.add('visible');
  if(options.action)$('button',element).onclick=()=>{element.classList.remove('visible');options.action.run();};
  statusTimer=setTimeout(()=>{element.classList.remove('visible');element.classList.remove('has-action');},options.action?8000:3200);
};
const pad = () => manifest.padding ?? 32;
const sourceURL = item => nativeURL(item.source);
const sprite = (item, side, compact=false, page=0) => nativeURL(compact ? side==='left'?item.compactLeft:item.compactRight : item.pages?.[page]?.[side] || item[side]);
const dimensions = (obj, compact=false) => ({width:compact?64:obj.item.width,height:compact?60:obj.item.height});
const hookX = (obj,compact=false) => obj.side==='left'?44:(compact?20:obj.item.width-44);
const hingeSign = obj => obj.side==='left'?1:-1;
const alive = token => token===run;

function renderSprite(obj, button, compact) {
  const {width,height}=dimensions(obj,compact),hook=hookX(obj,compact),padding=pad();
  Object.assign(button.style,{left:`${-hook}px`,top:'-26px',width:`${width}px`,height:`${height}px`});
  $('img',button).src=sprite(obj.item,obj.side,compact,obj.page);
  let text=$('.edited-note-text',button);if(obj.item.textContent!==undefined&&!compact){if(!text){text=document.createElement('span');text.className='edited-note-text';button.append(text);}text.textContent=obj.item.textContent;text.style.left=obj.side==='left'?'33px':'27px';}
  if(obj.item.previewPages&&!compact){let preview=$('.edited-preview',button);if(!preview){preview=new Image();preview.className='edited-preview';preview.draggable=false;preview.alt='编辑后文件的实际内容';button.append(preview);}preview.src=obj.item.previewPages[obj.page]||obj.item.previewPages[0];Object.assign(preview.style,{left:`${obj.side==='left'?15:9}px`,top:'44px',width:`${obj.item.width-24}px`,height:`${obj.item.height-53}px`});let clip=$('.edited-clip-occluder',button);if(!clip){clip=new Image();clip.className='edited-clip-occluder';clip.draggable=false;clip.alt='';button.append(clip);}clip.src=sprite(obj.item,obj.side,false,obj.page);Object.assign(clip.style,{left:`${-padding}px`,top:`${-padding}px`,width:`${width+padding*2}px`,height:`${height+padding*2}px`,clipPath:`inset(0 0 calc(100% - ${padding+54}px) 0)`});}
  Object.assign($('img',button).style,{left:`${-padding}px`,top:`${-padding}px`,width:`${width+padding*2}px`,height:`${height+padding*2}px`});
}
function render(obj) {
  obj.el.style.left=`${obj.x}px`;obj.el.style.top=`${obj.y}px`;
  obj.el.classList.toggle('compact',obj.compact);
  obj.el.classList.toggle('floating',!obj.docked);
  renderSprite(obj,obj.expandedButton,false);renderSprite(obj,obj.compactButton,true);
  obj.expandedButton.hidden=obj.compact;obj.compactButton.hidden=!obj.compact;
  const title=$('.object-name',obj.el);title.textContent=obj.item.title;
  Object.assign(title.style,{left:`${-hookX(obj,obj.compact)}px`,top:`${dimensions(obj,obj.compact).height-16}px`});
  const pages=$('.page-controls',obj.el);
  if(pages){Object.assign(pages.style,{left:`${-hookX(obj)+10}px`,top:`${obj.item.height-6}px`});$('span',pages).textContent=`${obj.page+1} / ${obj.item.pages.length}`;$('[data-page="-1"]',pages).disabled=obj.page===0;$('[data-page="1"]',pages).disabled=obj.page===obj.item.pages.length-1;}
}
function makeObject(item,{x,y,side='left',compact=false,docked=true,initial=false,page=0}={}) {
  const id=++sequence;const el=document.createElement('article');el.className=`native-object ${initial?'initial-object':''}`;el.setAttribute('aria-label',item.title);el.dataset.fileKind=item.kind;el.dataset.fileId=item.fileId;
  el.innerHTML=`<span class="nail" aria-hidden="true"></span><div class="assembly"><button class="native-state expanded-state" aria-label="${escapeHTML(item.title)}，原生预览"><img alt="${escapeHTML(item.title)}的桌面端实际夹取样式" draggable="false"></button><button class="native-state compact-state" aria-label="展开${escapeHTML(item.title)}"><img alt="桌面端真实收起状态" draggable="false"></button><button class="move-grip" aria-label="拖动夹子移动，点击收放" title="拖动夹子移动 · 点击收放"></button></div><span class="object-name"></span>${item.pages?.length>1?'<div class="page-controls"><button data-page="-1" aria-label="上一页">‹</button><span></span><button data-page="1" aria-label="下一页">›</button></div>':''}`;
  const obj={id,item,x,y,side,compact,docked,page,sticky:!compact,el,expandedButton:$('.expanded-state',el),compactButton:$('.compact-state',el),busy:false};
  objects.set(id,obj);$('#objects').append(el);render(obj);
  const grip=$('.move-grip',el);
  grip.addEventListener('pointerdown',e=>{
    if(e.button!==0 || obj.busy)return;e.preventDefault();stopDemo(false);clearTimeout(obj.hoverTimer);clearTimeout(obj.leaveTimer);
    dragging={obj,id:e.pointerId,start:{x:e.clientX,y:e.clientY},x:obj.x,y:obj.y,moved:false,lastX:e.clientX,lastY:e.clientY,wasCompact:obj.compact};grip.setPointerCapture(e.pointerId);el.style.zIndex=++z;
  });
  obj.compactButton.addEventListener('click',()=>setExpanded(obj,true));
  obj.expandedButton.addEventListener('click',()=>{if(!obj.busy)copyItem(obj.item,obj.expandedButton);});
  obj.expandedButton.draggable=true;obj.expandedButton.addEventListener('dragstart',event=>{if(manual||obj.busy){event.preventDefault();return;}if(!files.writeDrag(event.dataTransfer,obj.item))event.preventDefault();else feedback.play('copy',obj.expandedButton);});
  for(const surface of [obj.compactButton,obj.expandedButton,grip]){
    surface.addEventListener('pointerenter',()=>{clearTimeout(obj.leaveTimer);if(obj.compact&&!dragging&&!manual){clearTimeout(obj.hoverTimer);obj.hoverTimer=setTimeout(()=>setExpanded(obj,true,true),350);}});
    surface.addEventListener('pointerleave',()=>{clearTimeout(obj.hoverTimer);if(!obj.sticky&&!dragging){obj.leaveTimer=setTimeout(()=>setExpanded(obj,false),450);}});
  }
  $$('[data-page]',el).forEach(b=>b.addEventListener('click',()=>turnPage(obj,Number(b.dataset.page))));
  obj.expandedButton.addEventListener('wheel',e=>{if(!obj.item.pages?.length)return;e.preventDefault();const now=performance.now();if(now-(obj.lastWheel||-Infinity)<650)return;obj.lastWheel=now;turnPage(obj,Math.sign(e.deltaY));},{passive:false});
  return obj;
}
async function setExpanded(obj,expanded,temporary=false) {
  if(obj.busy || obj.compact===!expanded)return;
  clearTimeout(obj.hoverTimer);clearTimeout(obj.leaveTimer);obj.busy=true;obj.sticky=expanded&&!temporary;
  const assembly=$('.assembly',obj.el);const angle=HINGE.angle*hingeSign(obj);obj.el.style.zIndex=++z;
  if(expanded){obj.compact=false;render(obj);if(animated())await assembly.animate([{transform:`rotate(${angle}deg)`,opacity:.3},{transform:'rotate(-2deg)',opacity:1,offset:.68},{transform:'rotate(.4deg)',offset:.86},{transform:'rotate(0deg)'}],{duration:HINGE.settle,easing:'cubic-bezier(.2,.7,.25,1)'}).finished;}
  else{if(animated())await assembly.animate([{transform:'rotate(0deg)',opacity:1},{transform:`rotate(${angle}deg)`,opacity:0}],{duration:HINGE.close,easing:'ease-in-out'}).finished;obj.compact=true;render(obj);}
  obj.busy=false;
}
async function turnPage(obj,step) {
  if(obj.busy||obj.compact||!step)return;
  const next=clamp(obj.page+step,0,obj.item.pages.length-1);if(next===obj.page)return;obj.busy=true;
  const image=$('img',obj.expandedButton),old=new Image();
  const page=obj.item.pages[obj.page],surface=page[obj.side==='left'?'surfaceLeft':'surfaceRight'];
  old.src=nativeURL(surface);Object.assign(old.style,{left:`${obj.side==='left'?15:9}px`,top:'44px',width:`${obj.item.width-24}px`,height:`${obj.item.height-53}px`,transformOrigin:'0 50%'});
  obj.expandedButton.append(old);obj.page=next;image.src=sprite(obj.item,obj.side,false,next);
  if(obj.item.previewPages)renderSprite(obj,obj.expandedButton,false);
  if(animated())await old.animate([{transform:'perspective(850px) rotateY(0deg)',opacity:1},{transform:`perspective(850px) rotateY(${step>0?-105:105}deg)`,opacity:0}],{duration:480,easing:'cubic-bezier(.25,.6,.3,1)',fill:'forwards'}).finished;
  old.remove();obj.busy=false;render(obj);feedback.play('page',obj.expandedButton);status(obj.item.title,`原文件第 ${obj.page+1} 页`,{kind:'page'});
}
function moveDrag(e){const d=dragging;if(!d||d.id!==e.pointerId)return;const dx=e.clientX-d.start.x,dy=e.clientY-d.start.y;if(Math.hypot(dx,dy)>4)d.moved=true;if(!d.moved)return;d.obj.x=d.x+dx;d.obj.y=d.y+dy;d.obj.el.classList.add('moving');d.obj.el.style.setProperty('--angle',`${clamp((e.clientX-d.lastX)*.3,-7,7)}deg`);d.lastX=e.clientX;d.lastY=e.clientY;render(d.obj);}
function endDrag(){
  const d=dragging;if(!d)return;dragging=null;d.obj.el.classList.remove('moving');d.obj.el.style.setProperty('--angle','0deg');
  if(!d.moved){setExpanded(d.obj,d.wasCompact);return;}
  if(environment.isTrashPoint(d.lastX,d.lastY)){environment.discard({item:d.obj.item,x:d.obj.x,y:d.obj.y,side:d.obj.side,compact:d.obj.compact,docked:d.obj.docked,page:d.obj.page});feedback.move('remove',d.obj.compact?d.obj.compactButton:d.obj.expandedButton,$('[data-app=trash]'));d.obj.el.remove();feedback.cleanup();objects.delete(d.obj.id);status('已移到废纸篓',d.obj.item.title,{kind:'remove',action:{label:'撤销',run:()=>environment.undoTrash()}});return;}
  const side=d.lastX<42?'left':d.lastX>innerWidth-42?'right':null;d.obj.docked=!!side;
  if(side){d.obj.side=side;d.obj.x=side==='left'?44:innerWidth-44;render(d.obj);setExpanded(d.obj,false);}else render(d.obj);
}
function cursorAt(x,y,pose='open'){
  if((!gesture.active&&!manual)||(!hasPointer&&!manual)){cursor.hidden=true;return;}
  cursor.hidden=false;cursor.style.transform=`translate(${x-8}px,${y-26}px)`;$('.metal',cursor).src=nativeURL(manifest.cursor?.[pose]||`cursor-${pose}.png`);
}
function syncCapture(){
  let topLayer=$('#capture-visuals');
  if(!topLayer){topLayer=document.createElement('div');topLayer.id='capture-visuals';topLayer.setAttribute('popover','manual');document.body.append(topLayer);}
  const overDialog=dialog.open&&(gesture.active||!!manual),visualHost=overDialog?topLayer:document.body;
  for(const visual of [cursor,$('#target-glow')])if(visual&&visual.parentElement!==visualHost)visualHost.append(visual);
  if(overDialog&&!topLayer.matches(':popover-open'))topLayer.showPopover();
  else if(!overDialog&&topLayer.matches(':popover-open'))topLayer.hidePopover();
  document.body.classList.toggle('capture-on',(gesture.active||!!manual));
  if(!gesture.active)environment?.clearAim();
  else environment?.aimAt(point.x,point.y);
  cursorAt(point.x,point.y,manual?.ready?'closed':'open');
}
function stopDemo(announce=true){
  const canceledSource=manual?.source?.element;run++;gesture.cancel();if(manual){manual.source?.element.classList.remove('aiming','being-clamped');manual=null;}
  cursor.classList.remove('holding');environment?.clearAim();$('#flight-layer').replaceChildren();syncCapture();
  if(announce){feedback.play('cancel',canceledSource||$('#demo-status'));status('已取消夹取','松开 Option，再按住即可重新夹取',{kind:'cancel'});}
}
function modifierDown(event){
  if((event.metaKey||event.ctrlKey)&&event.key.toLowerCase()==='m'&&dialog.open){event.preventDefault?.();environment.minimizePanel(dialog,dialog.dataset.panelTitle);return;}
  if(event.key==='Alt'&&!event.metaKey&&!event.ctrlKey&&!event.shiftKey){event.preventDefault?.();gesture.hold();syncCapture();}
  else if(event.key==='Escape'&&(manual||gesture.active))stopDemo();
  else if(gesture.held&&event.key!=='Alt')stopDemo(false);
}
function modifierUp(event){
  if(event.key!=='Alt')return;event.preventDefault?.();
  // Mouse-up commits the drop. Releasing Option during its settling animation
  // must not cancel that completed gesture; releasing it earlier does cancel.
  if(manual&&!manual.released)stopDemo(false);
  gesture.unhold();syncCapture();
}
async function grasp(item,source,to,token){
  const rect=source.visual.getBoundingClientRect(),image=new Image();image.src=sourceURL(item);image.className='flight-item';$('#flight-layer').append(image);const start=performance.now();
  return new Promise(resolve=>{function frame(now){
    if(!alive(token)){image.remove();resolve(false);return;}
    const p=clamp((now-start)/(animated()?540:1)),jaw=manual?.token===token?(manual.released?manual.destination:point):to;
    const sample=pickupSample(p,rect,jaw,item.kind);Object.assign(image.style,{left:`${sample.x}px`,top:`${sample.y}px`,width:`${sample.width}px`,height:`${sample.height}px`,transform:`rotate(${sample.angle}deg) scaleY(${1-sample.compression})`});cursorAt(jaw.x,jaw.y,p<.48?'open':p<.75?'half':'closed');
    if(p<1)requestAnimationFrame(frame);else{image.remove();$('.carry',cursor).src=sourceURL(item);cursor.classList.add('holding');resolve(true);}
  }requestAnimationFrame(frame);});
}
async function beginCapture(event,source){
  if(event.button!==0||manual)return;
  if(!files.get(source.item)?.file){event.preventDefault();status('正在重新读取文件',source.item.title);files.ensure(source.item).then(()=>status('文件已就绪','请再次夹取')).catch(()=>status('文件暂时不可用','其他内容仍可正常夹取'));return;}
  if(!gesture.press())return;
  event.preventDefault();run++;const token=run;
  hasPointer=true;point.x=event.clientX;point.y=event.clientY;
  manual={item:source.item,source,token,start:{x:event.clientX,y:event.clientY},ready:false,released:false};
  environment.clearAim();document.dispatchEvent(new Event('clamp-close-system-menu'));source.element.classList.add('being-clamped');source.element.setPointerCapture(event.pointerId);
  if(source.prepare){try{const item=await source.prepare();if(!alive(token))return;source.item=item;manual.item=item;}catch{if(alive(token)){stopDemo(false);status('文字暂时无法保存','请稍后再试');}return;}}
  grasp(source.item,source,manual.start,token).then(ok=>{if(ok&&manual?.token===token){manual.ready=true;source.element.classList.remove('aiming','being-clamped');if(manual.released)finishManual();}});
}
async function copyItem(item,target){
  try{await files.ensure(item);}catch{status('未能复制','原文件暂时不可用，请稍后重试');return;}
  environment.clipboard=item;
  try{if(item.kind==='note'||item.kind==='code'){await navigator.clipboard?.writeText(await files.text(item));}
  else if(item.kind==='photo'&&window.ClipboardItem){await navigator.clipboard?.write([new ClipboardItem({'image/png':files.get(item).file})]);}}
  catch{/* Browser file clipboard remains available to the desktop apps. */}
  feedback.play('copy',target||[...objects.values()].find(obj=>obj.item.fileId===item.fileId)?.expandedButton);status('已复制',`${item.title} · 可粘贴到网页访达或信息`,{kind:'copy'});
}
function showAbout(){showDialog('屏幕夹子',`<div class="about-app"><img src="./assets/app-icon.webp" alt=""><div><h2>把灵感，夹在手边。</h2><p>文字、照片、文稿与文件，随手夹住，留在眼前。</p></div></div><a class="download" href="https://github.com/Quartzsyr/ClampEverything/releases/download/v1.7.16/ClampEverything-1.7.16-arm64.dmg">下载 Mac 版 · v1.7.16 ↓</a><p>Apple Silicon · macOS 14+ · 13.9 MiB</p><p class="release-links"><a href="https://github.com/Quartzsyr/ClampEverything/releases/tag/v1.7.16" target="_blank" rel="noopener">详细更新说明 ↗</a><a href="https://github.com/Quartzsyr/ClampEverything/releases/download/v1.7.16/ClampEverything-1.7.16-arm64.dmg.sha256">SHA-256 校验</a></p><p class="release-signing">开发签名，尚未经过 Apple 公证。</p><div class="developer"><b>Quartz</b><p>UESTC</p><a href="mailto:SYRQuartz@gmail.com">SYRQuartz@gmail.com</a></div>`);}
function showDeveloper(){showDialog('开发者信息',`<div class="developer-profile"><img src="./assets/app-icon.webp" alt=""><h2>Quartz</h2><p>UESTC</p><a href="mailto:SYRQuartz@gmail.com">SYRQuartz@gmail.com</a><small>屏幕夹子 · Clamp Everything</small><a href="https://github.com/Quartzsyr/ClampEverything" target="_blank" rel="noopener">GitHub 项目 ↗</a></div>`);}
function showDialog(title,body){
  document.dispatchEvent(new Event('clamp-close-system-menu'));environment?.releasePanel();stopDemo(false);dialog.removeAttribute('style');dialog.dataset.panelTitle=title;
  $('#dialog-content').innerHTML=`<div class="dialog-head"><div class="traffic-lights"><button class="traffic close" data-panel-control="close" aria-label="关闭"><span>×</span></button><button class="traffic minimize" data-panel-control="minimize" aria-label="收入 Dock"><span>−</span></button><button class="traffic zoom" data-panel-control="zoom" aria-label="缩放面板"><span>＋</span></button></div><h2 id="dialog-title">${title}</h2><span class="panel-title-spacer"></span></div><div class="dialog-body">${body}</div>${['n','e','s','w','ne','nw','se','sw'].map(edge=>`<div class="window-edge" data-panel-resize="${edge}" aria-label="调整面板大小"></div>`).join('')}`;
  $('[data-panel-control=close]').onclick=()=>{environment?.releasePanel();dialog.close();};
  $('[data-panel-control=minimize]').onclick=()=>environment.minimizePanel(dialog,title);
  let savedStyle=null;$('[data-panel-control=zoom]').onclick=()=>{if(savedStyle!==null){dialog.style.cssText=savedStyle;savedStyle=null;}else{savedStyle=dialog.style.cssText;Object.assign(dialog.style,{margin:'0',left:'16px',top:'48px',width:`${innerWidth-32}px`,height:`${innerHeight-80}px`,maxWidth:'none',maxHeight:'none'});}};
  dialog.showModal();environment?.showPanel(dialog,title);$('#active-app').textContent='屏幕夹子';
}
function bindDialogGeometry(){
  let state=null;
  const finish=()=>{state=null;dialog.classList.remove('interacting');};
  dialog.addEventListener('pointerdown',event=>{
    if(event.button!==0||event.target.closest('button,a,input'))return;
    const header=event.target.closest('.dialog-head'),edge=event.target.closest('[data-panel-resize]');if(!header&&!edge)return;
    event.preventDefault();const r=dialog.getBoundingClientRect();state={pointer:event.pointerId,x:event.clientX,y:event.clientY,left:r.x,top:r.y,width:r.width,height:r.height,edge:edge?.dataset.panelResize};
    Object.assign(dialog.style,{margin:'0',left:`${r.x}px`,top:`${r.y}px`,width:`${r.width}px`,height:`${r.height}px`});dialog.classList.add('interacting');(header||edge).setPointerCapture(event.pointerId);
  });
  document.addEventListener('pointermove',event=>{
    if(!state||state.pointer!==event.pointerId)return;const s=state,dx=event.clientX-s.x,dy=event.clientY-s.y;
    let left=s.left,top=s.top,right=s.left+s.width,bottom=s.top+s.height;
    if(s.edge){const minW=Math.min(300,innerWidth-24),minH=Math.min(230,innerHeight-70);if(s.edge.includes('e'))right=clamp(right+dx,left+minW,innerWidth-8);if(s.edge.includes('w'))left=clamp(left+dx,8,right-minW);if(s.edge.includes('s'))bottom=clamp(bottom+dy,top+minH,innerHeight-8);if(s.edge.includes('n'))top=clamp(top+dy,44,bottom-minH);}
    else{left=clamp(left+dx,8,Math.max(8,innerWidth-s.width-8));top=clamp(top+dy,44,Math.max(44,innerHeight-s.height-8));right=left+s.width;bottom=top+s.height;}
    Object.assign(dialog.style,{left:`${left}px`,top:`${top}px`,width:`${right-left}px`,height:`${bottom-top}px`});
  });
  document.addEventListener('pointerup',finish);document.addEventListener('pointercancel',finish);dialog.addEventListener('close',()=>{finish();environment?.panelClosed(dialog);syncCapture();});window.addEventListener('blur',finish);window.addEventListener('resize',()=>{finish();if(!dialog.open)return;const r=dialog.getBoundingClientRect(),width=Math.min(r.width,innerWidth-16),height=Math.min(r.height,innerHeight-60);Object.assign(dialog.style,{margin:'0',width:`${width}px`,height:`${height}px`,left:`${clamp(r.x,8,Math.max(8,innerWidth-width-8))}px`,top:`${clamp(r.y,44,Math.max(44,innerHeight-height-8))}px`});});
}
function showSettings(){showDialog('设置',`<div class="setting-row"><label for="motion-setting">播放拟物动画</label><input id="motion-setting" type="checkbox" ${motion?'checked':''}></div><div class="wallpaper-settings"><div class="setting-row"><label for="wallpaper-auto">随机轮换壁纸 · 每 5 分钟</label><input id="wallpaper-auto" type="checkbox" ${wallpapers.automatic?'checked':''}></div><div class="wallpaper-choices">${WALLPAPERS.map(p=>`<button data-wallpaper="${p.id}" aria-label="使用${p.name}壁纸" aria-pressed="${p.id===wallpapers.current}"><img src="${p.url}" alt="" loading="lazy"><span>${p.name}</span></button>`).join('')}</div><button class="wallpaper-next" id="wallpaper-next">换一张壁纸 ↻</button><p class="reset-note">选择缩略图可固定壁纸。自动轮换在后台暂停，操作时稍后切换。</p></div><button id="reset-desktop">还原演示桌面与文件</button><p class="reset-note">恢复初始示例，清除本地编辑与废纸篓内容。</p><div class="developer"><h3>开发者信息</h3><b>Quartz</b><p>UESTC</p><a href="mailto:SYRQuartz@gmail.com">SYRQuartz@gmail.com</a></div>`);$('#motion-setting').onchange=e=>{motion=e.target.checked;};$('#wallpaper-auto').onchange=e=>wallpapers.setAutomatic(e.target.checked);$('#wallpaper-next').onclick=()=>wallpapers.next();$$('button[data-wallpaper]').forEach(button=>button.onclick=async()=>{if(await wallpapers.select(button.dataset.wallpaper))wallpapers.setAutomatic(false);});$('#reset-desktop').onclick=()=>{dialog.close();layoutInitial();};}
function showHelp(){showDialog('就在桌面上，随手夹取',`<p>平时单击选择文件，双击或 Enter 打开；直接拖动桌面图标可以重新摆放，Esc 取消拖动，位置会在此浏览器保留。文字可以正常选择；按住 Option 可夹取标题、文件名和网页正文，选中一段文字则只夹这一段。按住 ⌥ Option（Windows / Linux 为 Alt），鼠标变成夹子，再按下内容、拖到想放的位置，松开鼠标放置。松开按键恢复普通鼠标。Esc 或右键取消。</p><p>拖金属夹移动整件物件，点金属夹收放。靠近左右边缘放置会收起，悬停再展开。点内容复制，拖出内容可复制到访达。</p><p>信息输入框可输入，Enter 发送，Shift+Enter 换行；备忘录可以直接编辑，新文字也可按住 Option 夹取。信息会按内容回复文字、照片、影片或文档，可试着发“照片”“视频”“计划”或“代码”。Word 可编辑正文和格式，代码可直接修改，⌘S 保存并支持下载，刷新后恢复工作文件。图标可拖入废纸篓，⌘⌫ 移入，⌘Z 放回。刷新网页会找回所有桌面示例文件，保留编辑内容和 Dock 快捷入口；左上夹子菜单也可恢复桌面文件。访达支持搜索文件。Dock 打开应用；拖动标题栏移动窗口，拖边缘或四角调整大小。设置、帮助、开发者和应用信息面板也支持移动与缩放，黄色按钮以神奇效果收入 Dock，再点对应应用图标展开。文件可拖入 Dock 保留快捷入口，拖出可移除入口，原文件保留。左上角夹子 Logo 打开应用菜单。窗口可以关闭、最小化和缩放。文件右键可打开、快速查看或下载原文件。网页、图片、PDF、Word、音视频、代码和文本均来自专门制作的真实演示文件。</p>`);}
function layoutInitial(){stopDemo(false);for(const obj of objects.values())obj.el.remove();objects.clear();environment?.reset();}
function bind(){
  document.addEventListener('clamp-wallpaper-change',()=>{const checkbox=$('#wallpaper-auto');if(checkbox)checkbox.checked=wallpapers.automatic;$$('button[data-wallpaper]').forEach(button=>button.setAttribute('aria-pressed',String(button.dataset.wallpaper===wallpapers.current)));});
  bindDialogGeometry();bindSystemMenu({canCapture:()=>gesture.held||!!manual,actions:{about:showAbout,developer:showDeveloper,settings:showSettings,help:showHelp,wallpaper:()=>wallpapers.next(),desktop:()=>environment.restoreDesktopFiles(),minimize:()=>environment.minimizeAll(),restore:()=>environment.restoreAll(),download:()=>{location.href='https://github.com/Quartzsyr/ClampEverything/releases/download/v1.7.16/ClampEverything-1.7.16-arm64.dmg';}}});
  // A consumed hold still owns the corresponding click, including links and
  // direct button handlers. Capturing their label must never activate them.
  document.addEventListener('click',event=>{if(event.altKey||gesture.held||manual){event.preventDefault();event.stopImmediatePropagation();}},true);
  document.addEventListener('click',event=>{if(event.altKey||gesture.active||manual)return;const action=event.target.closest('[data-action]')?.dataset.action;
    if(action==='about')showAbout();if(action==='settings')showSettings();if(action==='help')showHelp();if(action==='finder')environment.openFinder();if(action==='edit')environment.pasteFile();if(action==='windows')environment.showWindowMenu();});
  document.addEventListener('pointermove',event=>{hasPointer=true;point.x=event.clientX;point.y=event.clientY;moveDrag(event);if(manual?.ready)cursorAt(event.clientX,event.clientY,'closed');else if(!manual)cursorAt(event.clientX,event.clientY);});
  document.addEventListener('pointerup',event=>{endDrag();if(manual&&gesture.release()){manual.released=true;manual.destination={x:event.clientX,y:event.clientY};if(manual.ready)finishManual();}});
  document.addEventListener('pointercancel',()=>{dragging=null;stopDemo(false);gesture.unhold();syncCapture();});
  document.addEventListener('keydown',modifierDown);document.addEventListener('keyup',modifierUp);
  window.addEventListener('clamp-modifier',event=>{(event.detail.type==='keydown'?modifierDown:modifierUp)(event.detail);});
  document.addEventListener('contextmenu',event=>{if(manual||gesture.active){event.preventDefault();stopDemo();event.stopImmediatePropagation();}},true);
  window.addEventListener('blur',()=>{if(manual||gesture.held){stopDemo(false);gesture.unhold();syncCapture();}});
  dialog.addEventListener('click',event=>{if(event.target===dialog){const rect=dialog.getBoundingClientRect();if(event.clientX<rect.left||event.clientX>rect.right||event.clientY<rect.top||event.clientY>rect.bottom)dialog.close();}});
  document.documentElement.addEventListener('pointerleave',()=>{cursor.hidden=true;environment?.clearAim();});
  let resize;window.addEventListener('resize',()=>{clearTimeout(resize);resize=setTimeout(()=>{stopDemo(false);for(const obj of objects.values()){obj.x=obj.docked?(obj.side==='left'?44:innerWidth-44):clamp(obj.x,44,innerWidth-44);obj.y=clamp(obj.y,26,Math.max(26,innerHeight-$('#desktop').getBoundingClientRect().top-(obj.item.height-26)-150));render(obj);}},180);});
}
function finishManual(){
  const current=manual;if(!current)return;const destination=current.destination,edge=destination.x<42?'left':destination.x>innerWidth-42?'right':null;
  const side=edge||(destination.x>innerWidth/2?'right':'left');
  const hook=side==='left'?44:current.item.width-44;
  const x=edge?(edge==='left'?44:innerWidth-44):clamp(destination.x,hook+5,innerWidth-current.item.width+hook-5);
  const desktopTop=$('#desktop').getBoundingClientRect().top;
  const obj=makeObject(current.item,{x,y:clamp(destination.y-desktopTop,26,Math.max(26,innerHeight-desktopTop-(current.item.height-26)-150)),side,compact:!!edge,docked:!!edge});
  obj.el.style.zIndex=++z;current.source.element.classList.remove('aiming','being-clamped');manual=null;gesture.cancel();syncCapture();cursor.classList.remove('holding');feedback.play(edge?'pin':'receive',edge?obj.compactButton:obj.expandedButton);status(edge?'已收在屏幕边缘':'已夹在手边',current.item.title,{kind:'pin'});
}
async function init(){
  document.body.classList.add('load-pending');const response=await fetch(nativeURL('manifest.json'),{cache:'no-store'});if(!response.ok)throw new Error('原生素材尚未就绪');manifest=await response.json();await files.load([...manifest.items,...(manifest.extraItems||[])]);
  environment=createDesktop({manifest,nativeURL,files,animated,canCapture:()=>gesture.active,onCapture:beginCapture,onStatus:status,onSettings:showSettings,onAbout:showAbout,isCapturing:()=>!!manual,feedback,onCancel:stopDemo,onCopy:copyItem,onRestorePinned:entry=>makeObject(entry.item,entry)});
  bind();await environment.mount();document.body.classList.remove('load-pending');if(files.failures.size)status('桌面已就绪',`${files.failures.size} 个文件暂时不可用，其他内容可继续使用；再次夹取会重试`);else status('按住 ⌥ Option，随手夹取','普通鼠标单击选择、双击打开；按住 Option 夹取，松开鼠标放置');
}
function updateClock(){$('#clock').textContent=new Intl.DateTimeFormat('zh-CN',{weekday:'short',hour:'2-digit',minute:'2-digit',hour12:false}).format(new Date());}updateClock();setInterval(updateClock,30000);
init().catch(error=>{document.body.classList.remove('load-pending');status('原生演示素材加载失败','请刷新页面重试');console.error(error);});
