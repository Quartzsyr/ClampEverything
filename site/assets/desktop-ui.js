// The native TargetGlow.swift palette, contours and movement/dwell timing.
export function createTargetGlow({enabled, capturing}) {
  const ns='http://www.w3.org/2000/svg', overlay=document.createElementNS(ns,'svg');
  overlay.id='target-glow';overlay.setAttribute('aria-hidden','true');
  overlay.innerHTML='<defs><linearGradient id="aim-light" x2="1" y2="1"><stop stop-color="var(--aim-color)"/><stop offset=".5" stop-color="#ffffffe6"/><stop offset="1" stop-color="var(--aim-color)" stop-opacity=".75"/></linearGradient></defs><g class="aim-regions"></g>';
  document.body.append(overlay);
  let target=null,timer,lastX,lastY;
  const group=overlay.querySelector('g');
  function clear(){clearTimeout(timer);target?.classList.remove('aiming');target=null;overlay.classList.remove('visible','moving');group.replaceChildren();lastX=lastY=undefined;}
  function draw(){
    if(!target?.isConnected||!enabled()||capturing()){clear();return;}
    const kind=target.dataset.sourceKind, text=kind==='note'&&!target.matches('.desktop-file,.finder-file,.message-attachment');
    const style=text?'text':kind==='photo'?'image':kind==='web'?'link':kind==='folder'?'folder':'file';
    overlay.dataset.style=style;overlay.style.setProperty('--aim-color',({text:'#ffe6a6',image:'#73d1ff',link:'#66f0c2',folder:'#ffb352',file:'#baa6ff'})[style]);
    let regions=[];
    if(text){
      const root=target.querySelector('.message-lines')||target,walker=document.createTreeWalker(root,NodeFilter.SHOW_TEXT);
      while(walker.nextNode()){
        const node=walker.currentNode;if(!node.textContent.trim())continue;
        const range=document.createRange();range.selectNodeContents(node);
        regions.push(...range.getClientRects());
      }
    }else{
      const hit=document.elementFromPoint(lastX,lastY),underPointer=hit?.closest('img,video,canvas');
      const visual=target.contains(underPointer)?underPointer:target.querySelector('.file-icon,img,video,canvas,iframe')||target,rect=visual.getBoundingClientRect();
      if(visual.matches('img,video')&&getComputedStyle(visual).objectFit==='contain'){
        const w=visual.naturalWidth||visual.videoWidth,h=visual.naturalHeight||visual.videoHeight,s=Math.min(rect.width/w,rect.height/h);
        if(w&&h)regions=[{x:rect.x+(rect.width-w*s)/2,y:rect.y+(rect.height-h*s)/2,width:w*s,height:h*s}];
      }
      if(!regions.length)regions=[rect];
    }
    // Intersect with the actual scroll viewport instead of glowing through chrome.
    let clip={left:0,top:38,right:innerWidth,bottom:innerHeight};
    for(let parent=target.parentElement;parent&&parent!==document.body;parent=parent.parentElement){
      if(/auto|scroll|hidden|clip/.test(getComputedStyle(parent).overflow)){
        const r=parent.getBoundingClientRect();clip={left:Math.max(clip.left,r.left),top:Math.max(clip.top,r.top),right:Math.min(clip.right,r.right),bottom:Math.min(clip.bottom,r.bottom)};
      }
    }
    group.replaceChildren();
    for(const rect of regions.slice(0,24)){
      const x=Math.max(clip.left,rect.x)-2,y=Math.max(clip.top,rect.y)-2,w=Math.min(clip.right,rect.x+rect.width)-x+2,h=Math.min(clip.bottom,rect.y+rect.height)-y+2;
      if(w<4||h<4)continue;
      const shape=document.createElementNS(ns,style==='file'||style==='link'?'path':'rect');
      if(style==='file'){
        const l=Math.min(16,Math.min(w,h)*.3);shape.setAttribute('d',`M${x+l} ${y}H${x}V${y+l} M${x+w-l} ${y}H${x+w}V${y+l} M${x} ${y+h-l}V${y+h}H${x+l} M${x+w-l} ${y+h}H${x+w}V${y+h-l}`);
      }else if(style==='link')shape.setAttribute('d',`M${x} ${y+h}H${x+w}`);
      else for(const [key,value] of Object.entries({x,y,width:w,height:h,rx:style==='text'?2:style==='image'?3:7}))shape.setAttribute(key,value);
      group.append(shape);
      if(style==='text'){const rim=shape.cloneNode();rim.classList.add('aim-rim');group.append(rim);}
    }
    target.classList.add('aiming');overlay.classList.add('visible');overlay.classList.remove('moving');
  }
  function aimAt(x,y){
    if(!enabled()||capturing()){clear();return;}
    if(x===lastX&&y===lastY)return;lastX=x;lastY=y;
    const next=document.elementFromPoint(x,y)?.closest('[data-source]');
    clearTimeout(timer);
    if(next!==target){target?.classList.remove('aiming');target=next;overlay.classList.remove('visible');group.replaceChildren();}
    else if(target)overlay.classList.add('moving');
    if(target)timer=setTimeout(draw,280);
  }
  document.addEventListener('pointermove',e=>aimAt(e.clientX,e.clientY));
  document.addEventListener('scroll',()=>{if(target)draw();},true);
  window.addEventListener('resize',clear);window.addEventListener('blur',clear);
  return {aimAt,clear};
}

export function bindDock(dock,animated){
  dock.dockController?.abort();const controller=new AbortController();dock.dockController=controller;const options={signal:controller.signal};
  const tooltip=document.createElement('span');tooltip.className='dock-tooltip';tooltip.hidden=true;tooltip.setAttribute('aria-hidden','true');dock.append(tooltip);
  const reset=()=>{for(const button of dock.querySelectorAll('[data-app]')){button.style.setProperty('--dock-scale',1);button.style.setProperty('--dock-lift','0px');}tooltip.hidden=true;};
  function label(button){if(!button){tooltip.hidden=true;return;}tooltip.textContent=button.getAttribute('aria-label');tooltip.style.left=`${button.offsetLeft+button.offsetWidth/2}px`;tooltip.hidden=false;}
  dock.addEventListener('pointermove',event=>{
    for(const button of dock.querySelectorAll('[data-app]')){
      const r=button.getBoundingClientRect(),distance=Math.abs(event.clientX-r.x-r.width/2),scale=animated()?1+.14*Math.exp(-.5*(distance/42)**2):1;
      button.style.setProperty('--dock-scale',scale.toFixed(3));button.style.setProperty('--dock-lift',`${((scale-1)*28).toFixed(2)}px`);
    }
    label(event.target.closest('[data-app]'));
  },options);
  dock.addEventListener('pointerleave',reset,options);
  dock.addEventListener('focusin',event=>{if(event.target.matches(':focus-visible'))label(event.target.closest('[data-app]'));},options);
  dock.addEventListener('focusout',()=>{tooltip.hidden=true;},options);
  dock.addEventListener('click',()=>{tooltip.hidden=true;},options);
}
