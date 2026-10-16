import { createMeshRenderer } from './genie-renderer.js';
import './vendor/html2canvas/html2canvas.min.js';
const clamp=n=>Math.max(0,Math.min(1,n)),mix=(a,b,t)=>a+(b-a)*t,smooth=n=>{n=clamp(n);return n*n*(3-2*n);};
// Each texture row follows the same curved silhouette. The bottom narrows first;
// the top then feeds into the Dock. Reverse time restores the identical window.
export function genieRow(source,target,progress,row){
 const p=clamp(progress),t=clamp(row),neck=smooth(p/.46),feed=Math.pow(clamp((p-.16)/.84),1.75),edge=smooth(Math.pow(t,2.4-1.4*feed));
 const x=target.x+target.width*.22,w=target.width*.56,top=mix(source.y,target.y+target.height*.55,feed),bottom=mix(source.y+source.height,target.y+target.height*.55,neck);
 return {left:mix(mix(source.x,x,feed),mix(source.x,x,neck),edge),right:mix(mix(source.x+source.width,x+w,feed),mix(source.x+source.width,x+w,neck),edge),y:mix(top,bottom,t)};
}
function triangle(ctx,image,source,destination){
 const [a,b,c]=source,[A,B,C]=destination,det=(b.x-a.x)*(c.y-a.y)-(c.x-a.x)*(b.y-a.y);if(Math.abs(det)<.00001)return;
 const m11=((B.x-A.x)*(c.y-a.y)-(C.x-A.x)*(b.y-a.y))/det,m12=((B.y-A.y)*(c.y-a.y)-(C.y-A.y)*(b.y-a.y))/det;
 const m21=((C.x-A.x)*(b.x-a.x)-(B.x-A.x)*(c.x-a.x))/det,m22=((C.y-A.y)*(b.x-a.x)-(B.y-A.y)*(c.x-a.x))/det;
 const center={x:(A.x+B.x+C.x)/3,y:(A.y+B.y+C.y)/3},expanded=[A,B,C].map(point=>{const dx=point.x-center.x,dy=point.y-center.y,length=Math.hypot(dx,dy)||1;return {x:point.x+dx/length*.65,y:point.y+dy/length*.65};});
 ctx.save();ctx.beginPath();ctx.moveTo(expanded[0].x,expanded[0].y);ctx.lineTo(expanded[1].x,expanded[1].y);ctx.lineTo(expanded[2].x,expanded[2].y);ctx.closePath();ctx.clip();ctx.transform(m11,m12,m21,m22,A.x-m11*a.x-m21*a.y,A.y-m12*a.x-m22*a.y);ctx.drawImage(image,0,0);ctx.restore();
}
async function snapshot(el){
 let container;const r=el.getBoundingClientRect(),surfaces=[];
 // Rasterize the live same-origin document before cloning the outer window.
 // Otherwise a freshly cloned iframe can still be loading and paint blank.
 for(const frame of el.querySelectorAll('iframe')){try{const doc=frame.contentDocument;if(!doc?.body)continue;const key=`genie-${Date.now()}-${surfaces.length}`,parent=frame.parentElement;parent.dataset.genieFrame=key;const surface={key,parent,src:null};surfaces.push(surface);
   const image=await window.html2canvas(doc.documentElement,{backgroundColor:null,logging:false,scale:Math.min(devicePixelRatio||1,1.5),width:frame.clientWidth,height:frame.clientHeight,x:frame.contentWindow.scrollX,y:frame.contentWindow.scrollY,windowWidth:frame.clientWidth,windowHeight:frame.clientHeight,imageTimeout:1800,ignoreElements:node=>node.matches?.('iframe,script,.html2canvas-container')});
   surface.src=image.toDataURL();
 }catch{/* A cross-origin document cannot be read by a local animation. */}}
 for(const video of el.querySelectorAll('video')){try{const parent=video.parentElement,key=`genie-video-${Date.now()}-${surfaces.length}`,surface={key,parent,src:null};parent.dataset.genieFrame=key;surfaces.push(surface);
   const picture=document.createElement('canvas');picture.width=video.clientWidth;picture.height=video.clientHeight;const ctx=picture.getContext('2d');ctx.fillStyle='#171a17';ctx.fillRect(0,0,picture.width,picture.height);
   let visual=video;if(video.readyState<2){visual=new Image();visual.src=video.poster;await visual.decode();}const width=visual.videoWidth||visual.naturalWidth,height=visual.videoHeight||visual.naturalHeight,scale=Math.min(picture.width/width,picture.height/height);ctx.drawImage(visual,(picture.width-width*scale)/2,(picture.height-height*scale)/2,width*scale,height*scale);surface.src=picture.toDataURL();
 }catch{/* Preserve the player's own background if its media is not ready. */}}
 try{return await window.html2canvas(el,{backgroundColor:null,scale:Math.min(devicePixelRatio||1,1.5),logging:false,imageTimeout:1800,windowWidth:innerWidth,windowHeight:innerHeight,
   ignoreElements:node=>node.matches?.('iframe,video,#capture-visuals,.window-genie,.html2canvas-container,#target-glow,#system-menu'),
   onclone:async(doc,clone)=>{container=doc.defaultView?.frameElement;clone.style.animation='none';clone.style.visibility='visible';clone.style.opacity='1';if(clone.matches('dialog'))Object.assign(clone.style,{position:'fixed',margin:'0',left:`${r.x}px`,top:`${r.y}px`,width:`${r.width}px`,height:`${r.height}px`});
    for(const surface of surfaces){if(!surface.src)continue;const parent=clone.querySelector(`[data-genie-frame="${surface.key}"]`);if(parent){const img=doc.createElement('img');img.src=surface.src;Object.assign(img.style,{display:'block',width:'100%',height:'100%',objectFit:'fill'});parent.prepend(img);await img.decode();}}
    // html2canvas cannot paint object-fit. Give cloned media its actual contained
    // dimensions, and keep every iframe at its live scroll position.
    for(const media of clone.querySelectorAll('img,video')){const style=doc.defaultView.getComputedStyle(media);if(style.objectFit!=='contain')continue;const w=media.naturalWidth||media.videoWidth,h=media.naturalHeight||media.videoHeight;if(!w||!h)continue;const box=media.getBoundingClientRect(),s=Math.min(box.width/w,box.height/h);Object.assign(media.style,{objectFit:'fill',width:`${w*s}px`,height:`${h*s}px`,alignSelf:'center',justifySelf:'center'});}
   }
 });}finally{container?.remove();for(const surface of surfaces)delete surface.parent.dataset.genieFrame;}
}
export function createGenieMotion({animated}){
 const cached=new WeakMap(),operations=new Map();let sequence=0;
 function cancel(el){operations.get(el)?.cancel();}
 function cancelAll(){for(const operation of [...operations.values()])operation.cancel();}
 async function play(el,targetFor,restoring=false,onPrepared){
  cancel(el);if(!animated()){el.style.visibility='';el.inert=false;return true;}
  const token=++sequence,rect=el.getBoundingClientRect(),source={x:rect.x,y:rect.y,width:rect.width,height:rect.height};
  if(!source.width||!source.height)return true;
  let frame,host,mesh,settle,finished=false,oldInert=el.inert,oldVisibility=el.style.visibility;
  const done=new Promise(resolve=>settle=resolve);
  const finish=ok=>{if(finished)return;finished=true;cancelAnimationFrame(frame);host?.remove();mesh?.dispose();el.style.visibility=oldVisibility;el.inert=oldInert;delete el.dataset.windowMotion;if(operations.get(el)?.token===token)operations.delete(el);settle(ok);};
  operations.set(el,{token,cancel:()=>finish(false)});el.inert=true;el.dataset.windowMotion=restoring?'restoring':'preparing';
  let image=restoring?cached.get(el):null;
  if(!image){try{image=await snapshot(el);if(!restoring)cached.set(el,image);}catch{/* Unsupported paint styles use a live-window fallback. */}}
  if(finished)return done;
  const initialTarget=targetFor()?.getBoundingClientRect();if(!initialTarget?.width){finish(false);return done;}
  if(!image){
   const dx=initialTarget.x+initialTarget.width/2-source.x-source.width/2,dy=initialTarget.y+initialTarget.height/2-source.y-source.height/2;
   const keys=[{transform:'translate(0,0) scale(1)',opacity:1},{transform:`translate(${dx*.24}px,${dy*.38}px) scale(.7,.93)`,opacity:1,offset:.4},{transform:`translate(${dx}px,${dy}px) scale(.04,.015)`,opacity:0}];
   const animation=el.animate(restoring?[...keys].reverse().map(({offset,...key})=>key):keys,{duration:520,easing:'cubic-bezier(.4,0,.2,1)'});
   const operation=operations.get(el);operation.cancel=()=>{animation.cancel();finish(false);};animation.finished.then(()=>finish(true),()=>finish(false));return done;
  }
  host=document.createElement('div');host.className='window-genie';host.setAttribute('popover','manual');host.setAttribute('aria-hidden','true');host.dataset.direction=restoring?'restore':'minimize';host.dataset.motionWindow=el.dataset.window||'panel';
  const canvas=document.createElement('canvas'),dpr=Math.min(devicePixelRatio||1,1.5);canvas.width=Math.ceil(innerWidth*dpr);canvas.height=Math.ceil(innerHeight*dpr);host.append(canvas);document.body.append(host);host.showPopover();
  mesh=createMeshRenderer(canvas,image);let context;if(!mesh){const fallback=document.createElement('canvas');fallback.width=canvas.width;fallback.height=canvas.height;canvas.replaceWith(fallback);context=fallback.getContext('2d');context.scale(dpr,dpr);context.imageSmoothingEnabled=true;context.imageSmoothingQuality='high';}host.dataset.renderer=mesh?'mesh':'canvas';
  el.style.visibility='hidden';onPrepared?.();el.dataset.windowMotion=restoring?'restoring':'minimizing';const started=performance.now(),duration=restoring?640:690;
  function draw(now){
   if(finished)return;const elapsed=clamp((now-started)/duration),p=restoring?1-elapsed:elapsed,target=targetFor()?.getBoundingClientRect()||initialTarget;
   host.dataset.progress=p.toFixed(3);const alpha=1-smooth((p-.94)/.06),strips=80;if(mesh){const rows=Array.from({length:strips+1},(_,index)=>genieRow(source,target,p,index/strips));mesh.draw(rows,alpha);}else{context.clearRect(0,0,innerWidth,innerHeight);context.globalAlpha=alpha;
   for(let index=0;index<strips;index++){
    const t0=index/strips,t1=Math.min(1,(index+1)/strips+.0007),a=genieRow(source,target,p,t0),b=genieRow(source,target,p,t1),y0=t0*image.height,y1=t1*image.height;
    const L={x:a.left,y:a.y},R={x:a.right,y:a.y},l={x:b.left,y:b.y},r={x:b.right,y:b.y};
    triangle(context,image,[{x:0,y:y0},{x:image.width,y:y0},{x:0,y:y1}],[L,R,l]);
    triangle(context,image,[{x:image.width,y:y0},{x:image.width,y:y1},{x:0,y:y1}],[R,r,l]);
   }
   }
   if(elapsed<1)frame=requestAnimationFrame(draw);else finish(true);
  }
  frame=requestAnimationFrame(draw);return done;
 }
 window.addEventListener('resize',cancelAll);window.addEventListener('pagehide',cancelAll);
 return {minimize:(el,target,onPrepared)=>play(el,target,false,onPrepared),restore:(el,target)=>play(el,target,true),cancel,cancelAll};
}
