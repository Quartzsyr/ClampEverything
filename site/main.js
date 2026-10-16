import { HINGE, MATERIALS, clamp, pickupSample } from './motion.js';
import { HoldGesture } from './hold-gesture.js';

const $ = (s, root = document) => root.querySelector(s);
const $$ = (s, root = document) => [...root.querySelectorAll(s)];
const reduced = matchMedia('(prefers-reduced-motion: reduce)');
const nativeBase = new URL('./assets/native/', import.meta.url);
const nativeURL = path => new URL(path, nativeBase).href;
const dialog = $('#info-dialog');
const objects = new Map();
const gesture = new HoldGesture();
const labels = {photo:'照片',note:'便笺',document:'PDF',word:'Word',folder:'文件夹',web:'网页',code:'代码',audio:'音频',video:'视频',archive:'压缩包',file:'其他文件',group:'收纳夹'};
let manifest, selected, sequence=0, run=0, z=5, dragging=null, manual=null;
let motion = !reduced.matches;
let suppressSourceClick = 0;
let hasPointer = false;
const cursor = $('#demo-cursor');
const point = {x:0,y:0};
const animated = () => motion && !reduced.matches;
const escapeHTML = value => String(value).replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const pause = ms => new Promise(resolve=>setTimeout(resolve, animated()?ms:Math.min(ms,100)));
const status = (title,detail='') => {$('#demo-status').innerHTML=`<b>${escapeHTML(title)}</b>${detail?`<small>${escapeHTML(detail)}</small>`:''}`;};
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
function makeObject(item,{x,y,side='left',compact=false,docked=true,initial=false}={}) {
  const id=++sequence;const el=document.createElement('article');el.className=`native-object ${initial?'initial-object':''}`;el.setAttribute('aria-label',item.title);el.dataset.fileKind=item.kind;
  el.innerHTML=`<span class="nail" aria-hidden="true"></span><div class="assembly"><button class="native-state expanded-state" aria-label="${escapeHTML(item.title)}，原生预览"><img alt="${escapeHTML(item.title)}的桌面端实际夹取样式" draggable="false"></button><button class="native-state compact-state" aria-label="展开${escapeHTML(item.title)}"><img alt="桌面端真实收起状态" draggable="false"></button><button class="move-grip" aria-label="拖动夹子移动，点击收放" title="拖动夹子移动 · 点击收放"></button></div><span class="object-name"></span>${item.pages?.length>1?'<div class="page-controls"><button data-page="-1" aria-label="上一页">‹</button><span></span><button data-page="1" aria-label="下一页">›</button></div>':''}`;
  const obj={id,item,x,y,side,compact,docked,page:0,sticky:!compact,el,expandedButton:$('.expanded-state',el),compactButton:$('.compact-state',el),busy:false};
  objects.set(id,obj);$('#objects').append(el);render(obj);
  const grip=$('.move-grip',el);
  grip.addEventListener('pointerdown',e=>{
    if(e.button!==0 || obj.busy)return;e.preventDefault();stopDemo(false);clearTimeout(obj.hoverTimer);clearTimeout(obj.leaveTimer);
    dragging={obj,id:e.pointerId,start:{x:e.clientX,y:e.clientY},x:obj.x,y:obj.y,moved:false,lastX:e.clientX,lastY:e.clientY,wasCompact:obj.compact};grip.setPointerCapture(e.pointerId);el.style.zIndex=++z;
  });
  obj.compactButton.addEventListener('click',()=>setExpanded(obj,true));
  obj.expandedButton.addEventListener('click',()=>{if(!obj.busy)status(obj.item.title,'这是该原文件在桌面端的实际预览；点击「查看原文件」可打开源文件。');});
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
  if(animated())await old.animate([{transform:'perspective(850px) rotateY(0deg)',opacity:1},{transform:`perspective(850px) rotateY(${step>0?-105:105}deg)`,opacity:0}],{duration:480,easing:'cubic-bezier(.25,.6,.3,1)',fill:'forwards'}).finished;
  old.remove();obj.busy=false;render(obj);status(obj.item.title,`原文件第 ${obj.page+1} 页`);
}
function moveDrag(e){const d=dragging;if(!d||d.id!==e.pointerId)return;const dx=e.clientX-d.start.x,dy=e.clientY-d.start.y;if(Math.hypot(dx,dy)>4)d.moved=true;if(!d.moved)return;d.obj.x=clamp(d.x+dx,20,innerWidth-20);d.obj.y=clamp(d.y+dy,26,innerHeight-180);d.obj.el.classList.add('moving');d.obj.el.style.setProperty('--angle',`${clamp((e.clientX-d.lastX)*.3,-7,7)}deg`);d.lastX=e.clientX;d.lastY=e.clientY;render(d.obj);}
function endDrag(){const d=dragging;if(!d)return;dragging=null;d.obj.el.classList.remove('moving');d.obj.el.style.setProperty('--angle','0deg');if(!d.moved){setExpanded(d.obj,d.wasCompact);return;}const side=d.lastX<42?'left':d.lastX>innerWidth-42?'right':null;d.obj.docked=!!side;if(side){d.obj.side=side;d.obj.x=side==='left'?44:innerWidth-44;render(d.obj);setExpanded(d.obj,false);}else render(d.obj);}
function choose(item,play=false){selected=item;$('#source-image').src=sourceURL(item);$('#source-name').textContent=item.title;$('#source-download').href=nativeURL(item.file);$('#source-download').download=item.title;$$('[data-kind]').forEach(b=>b.classList.toggle('active',b.dataset.kind===item.kind));status('随手夹住，留在手边',item.title+' · 按住拖动，松手放置');}
function cursorAt(x,y,pose='open'){if(!hasPointer&&!manual){cursor.hidden=true;return;}cursor.hidden=false;cursor.style.transform=`translate(${x-8}px,${y-26}px)`;$('.metal',cursor).src=nativeURL(manifest.cursor?.[pose]||`cursor-${pose}.png`);}
function stopDemo(announce=true){document.body.classList.add('capture-on');run++;gesture.cancel();if(manual){manual=null;gesture.unhold();}cursor.hidden=dialog.open;cursor.classList.remove('holding');if(!dialog.open)cursorAt(point.x,point.y);$('#source-file').classList.remove('aiming');$('#flight-layer').replaceChildren();if(announce)status('已取消夹取','按住文件拖动，松手放置');}
async function grasp(item,from,to,token){const source=$('#source-image').getBoundingClientRect();const image=new Image();image.src=sourceURL(item);image.className='flight-item';$('#flight-layer').append(image);const start=performance.now();return new Promise(resolve=>{function frame(now){if(!alive(token)){image.remove();resolve(false);return;}const p=clamp((now-start)/(animated()?600:1));const jaw=manual?.token===token?(manual.released?manual.destination:point):to;const sample=pickupSample(p,source,jaw,item.kind);Object.assign(image.style,{left:`${sample.x}px`,top:`${sample.y}px`,width:`${sample.width}px`,height:`${sample.height}px`,transform:`rotate(${sample.angle}deg) scaleY(${1-sample.compression})`});cursorAt(jaw.x,jaw.y,p<.48?'open':p<.75?'half':'closed');if(p<1)requestAnimationFrame(frame);else{image.remove();$('.carry',cursor).src=sourceURL(item);cursor.classList.add('holding');resolve(true);}}requestAnimationFrame(frame);});}
function showDialog(title,body){stopDemo(false);$('#dialog-content').innerHTML=`<div class="dialog-head"><h2 id="dialog-title">${title}</h2><button aria-label="关闭">×</button></div><div class="dialog-body">${body}</div>`;$('.dialog-head button').onclick=()=>dialog.close();dialog.showModal();}
function showFiles(){showDialog('挑一份真实文件',`<p>这些文件先由 Mac 应用读取，再通过同一个原生预览组件导出夹取后的样式。</p><div class="file-grid">${manifest.items.map(item=>`<button data-select="${item.kind}"><img src="${sourceURL(item)}" alt=""><span>${escapeHTML(item.title)}</span><small>${labels[item.kind]} · 选择文件</small></button>`).join('')}</div>`);$$('[data-select]',dialog).forEach(b=>b.onclick=()=>{dialog.close();choose(manifest.items.find(i=>i.kind===b.dataset.select));});}
function showSettings(){showDialog('设置',`<div class="setting-row"><label for="motion-setting">播放拟物动画</label><input id="motion-setting" type="checkbox" ${motion?'checked':''}></div><button id="reset-desktop">重新整理演示桌面</button><div class="developer"><h3>开发者信息</h3><b>Quartz</b><p>UESTC</p><a href="mailto:SYRQuartz@gmail.com">SYRQuartz@gmail.com</a></div>`);$('#motion-setting').onchange=e=>{motion=e.target.checked;};$('#reset-desktop').onclick=()=>{dialog.close();layoutInitial();};}
function showHelp(){showDialog('把需要的东西，夹在手边',`<p>鼠标就是夹子。选择底部任意文件，在右侧按住它并拖动，松手放到桌面。按 Esc 或右键取消。</p><p>夹住后，点金属夹收放，拖金属夹移动。靠近左右边缘放置会收起，悬停再展开。</p><p>所有夹取后图像由桌面应用的 CardSurface 原生组件直接渲染；文稿页面来自真实 PDF / DOCX。网页用于展示，不访问你的系统文件。</p>`);}
function layoutInitial(){stopDemo(false);for(const obj of objects.values())obj.el.remove();objects.clear();const mobile=innerWidth<=700;
  const specs=mobile?[['photo',44,Math.max(365,innerHeight-350),'left',false]]:[['photo',44,innerHeight*.26,'left',false],['note',innerWidth-44,innerHeight*.50,'right',false],['document',innerWidth-44,innerHeight*.78,'right',true],['folder',44,innerHeight*.58,'left',true]];
  for(const [kind,x,y,side,compact]of specs){const item=manifest.items.find(i=>i.kind===kind);if(!item)continue;const o=makeObject(item,{x,y:y-36,side,compact,initial:true});if(kind!=='photo')o.el.classList.add('initial-secondary');}
}
function bind(){document.addEventListener('click',e=>{const action=e.target.closest('[data-action]')?.dataset.action;if(action==='play'){status('现在由你来夹','按住右侧文件拖动，松手放置');$('#source-file').focus();}if(action==='files')showFiles();if(action==='settings')showSettings();if(action==='help')showHelp();if(action==='about')showDialog('屏幕夹子',`<p>把照片、文稿与灵感夹在手边。</p><p>本页使用真实样本文件和桌面端原生渲染，展示当前开发版本的外观与动画。</p><a href="https://github.com/Quartzsyr/ClampEverything/releases/latest">下载最新公开 Mac 版 ↗</a><div class="developer"><b>Quartz</b><p>UESTC</p><a href="mailto:SYRQuartz@gmail.com">SYRQuartz@gmail.com</a></div>`);});
  $('#source-file').addEventListener('click',()=>{if(performance.now()<suppressSourceClick)return;if(!manual&&!gesture.active)status('鼠标已是夹子','按住这份文件拖动，松手放置；Esc 取消');});
  let aimTimer;const sourceFile=$('#source-file');sourceFile.addEventListener('pointerenter',()=>{clearTimeout(aimTimer);aimTimer=setTimeout(()=>sourceFile.classList.add('aiming'),250);});sourceFile.addEventListener('pointerleave',()=>{clearTimeout(aimTimer);if(!manual)sourceFile.classList.remove('aiming');});
  $('#source-file').addEventListener('pointerdown',e=>{if(e.button!==0)return;e.preventDefault();gesture.unhold();gesture.hold();run++;const token=run;manual={item:selected,token,start:{x:e.clientX,y:e.clientY},ready:false,released:false};gesture.press();$('#source-file').setPointerCapture(e.pointerId);grasp(selected,manual.start,manual.start,token).then(ok=>{if(ok&&manual?.token===token){manual.ready=true;$('#source-file').classList.remove('aiming');if(manual.released)finishManual();}});});
  document.addEventListener('pointermove',e=>{hasPointer=true;point.x=e.clientX;point.y=e.clientY;moveDrag(e);if(dialog.open){cursor.hidden=true;return;}if(manual?.ready)cursorAt(e.clientX,e.clientY,'closed');else if(!manual)cursorAt(e.clientX,e.clientY);});
  document.addEventListener('pointerup',e=>{endDrag();if(manual&&gesture.release()){manual.released=true;manual.destination={x:e.clientX,y:e.clientY};if(manual.ready)finishManual();}});
  document.addEventListener('pointercancel',()=>{dragging=null;stopDemo(false);gesture.unhold();});
  document.addEventListener('keydown',e=>{if(e.key==='Escape'){stopDemo();return;}if(dialog.open)return; });
  document.addEventListener('contextmenu',e=>{if(manual||gesture.active){e.preventDefault();stopDemo();}});window.addEventListener('blur',()=>{if(manual||gesture.active){stopDemo(false);gesture.unhold();}});
  dialog.addEventListener('click',e=>{if(e.target===dialog){const r=dialog.getBoundingClientRect();if(e.clientX<r.left||e.clientX>r.right||e.clientY<r.top||e.clientY>r.bottom)dialog.close();}});
  const dock=$('#type-picker');dock.addEventListener('pointermove',e=>{if(!animated())return;$$('button',dock).forEach(button=>{const r=button.getBoundingClientRect(),distance=Math.abs(e.clientX-r.x-r.width/2),scale=1+.38*Math.exp(-.5*(distance/58)**2);button.style.setProperty('--dock-scale',scale.toFixed(3));button.style.setProperty('--dock-lift',`${((scale-1)*22).toFixed(2)}px`);});});dock.addEventListener('pointerleave',()=>{$$('button',dock).forEach(button=>{button.style.setProperty('--dock-scale',1);button.style.setProperty('--dock-lift','0px');});});
  document.documentElement.addEventListener('pointerleave',()=>{cursor.hidden=true;});
  let resize;window.addEventListener('resize',()=>{clearTimeout(resize);resize=setTimeout(layoutInitial,180);});
}
function finishManual(){const m=manual;if(!m)return;suppressSourceClick=performance.now()+500;const p=m.destination,side=p.x<42?'left':p.x>innerWidth-42?'right':null;const obj=makeObject(m.item,{x:side==='left'?44:side==='right'?innerWidth-44:p.x,y:clamp(p.y-36,26,innerHeight-180),side:side||'left',compact:!!side,docked:!!side});obj.el.style.zIndex=++z;manual=null;gesture.cancel();document.body.classList.add('capture-on');cursorAt(p.x,p.y);cursor.classList.remove('holding');status('已夹住',m.item.title);}
async function init(){document.body.classList.add('load-pending','capture-on');const response=await fetch(new URL('manifest.json',nativeBase));if(!response.ok)throw new Error('原生素材尚未就绪');manifest=await response.json();if(!manifest.items?.length)throw new Error('缺少原生预览');
  $('#type-picker').innerHTML=manifest.items.map(item=>`<button data-kind="${item.kind}" aria-label="演示${labels[item.kind]}"><img src="${sourceURL(item)}" alt=""><span>${labels[item.kind]}</span></button>`).join('');$$('[data-kind]').forEach(b=>b.onclick=()=>choose(manifest.items.find(i=>i.kind===b.dataset.kind)));
  choose(manifest.items.find(i=>i.kind==='photo')||manifest.items[0],false);bind();layoutInitial();document.body.classList.remove('load-pending');document.body.classList.add('capture-on');status('鼠标已是夹子','按住右侧文件拖动，松手放置');
}
function updateClock(){$('#clock').textContent=new Intl.DateTimeFormat('zh-CN',{weekday:'short',hour:'2-digit',minute:'2-digit',hour12:false}).format(new Date());}updateClock();setInterval(updateClock,30000);
init().catch(error=>{document.body.classList.remove('load-pending');status('原生演示素材加载失败','请刷新页面重试');console.error(error);});
