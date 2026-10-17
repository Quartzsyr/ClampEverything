// Local visual responses share the system's reduced-motion setting. Never play sound.
export function createFeedback({animated=()=>true}={}){
 const running=new WeakMap(),marks=new Map();
 const cleanup=()=>{for(const [mark,target] of marks)if(!mark.isConnected||!target.isConnected){mark.remove();marks.delete(mark);}};
 const glyphs={copy:'✓',save:'✓',send:'↑',receive:'↓',download:'↓',pin:'＋',restore:'↶',page:'↗',cancel:'×',error:'!',open:'↗',select:'·',remove:'×',play:'▶',pause:'Ⅱ'};
 const colors={copy:'#71a58b',save:'#71a58b',send:'#85a8ce',receive:'#85a8ce',download:'#85a8ce',pin:'#b5a66c',restore:'#71a58b',page:'#b5a66c',cancel:'#9a9d94',error:'#cb7869',open:'#bbc9b3',select:'#bbc9b3',remove:'#cb7869',play:'#85a8ce',pause:'#9a9d94'};
 function play(kind,target,{badge=true}={}){
  if(!target?.isConnected)return;cleanup();for(const [mark,owner] of marks)if(owner===target){mark.remove();marks.delete(mark);}const color=colors[kind]||colors.select;
  target.dataset.feedback=kind;document.dispatchEvent(new CustomEvent('clamp-feedback',{detail:{kind}}));
  running.get(target)?.cancel();
  if(animated()){
   const frames=kind==='error'?[{translate:'0 0'},{translate:'-3px 0'},{translate:'3px 0'},{translate:'0 0'}]:kind==='open'?[{scale:'.975',opacity:.75},{scale:'1',opacity:1}]:kind==='send'?[{translate:'0 6px',opacity:.6},{translate:'0 0',opacity:1}]:[{boxShadow:`0 0 0 0 ${color}00`},{boxShadow:`0 0 0 3px ${color}77`,offset:.35},{boxShadow:`0 0 0 7px ${color}00`}];
   const effect=target.animate(frames,{duration:kind==='open'?220:460,easing:'cubic-bezier(.2,.7,.25,1)'});running.set(target,effect);effect.finished.catch(()=>{});
  }
  if(!badge||['open','select','play','pause'].includes(kind))return;
  const r=target.getBoundingClientRect(),mark=document.createElement('span');mark.className='interaction-mark';mark.dataset.kind=kind;mark.textContent=glyphs[kind]||'✓';mark.setAttribute('aria-hidden','true');mark.style.cssText=`left:${Math.max(10,Math.min(innerWidth-34,r.right-17))}px;top:${Math.max(42,Math.min(innerHeight-40,r.top+9))}px;--feedback-color:${color}`;document.body.append(mark);marks.set(mark,target);const remove=()=>{mark.remove();marks.delete(mark);};
  if(animated())mark.animate([{opacity:0,scale:'.75',translate:'0 3px'},{opacity:1,scale:'1',translate:'0 0',offset:.18},{opacity:1,offset:.7},{opacity:0,translate:'0 -5px'}],{duration:900,easing:'ease-out'}).finished.then(remove,remove);else setTimeout(remove,650);
 }
 function move(kind,source,destination){
  if(!source?.isConnected||!destination?.isConnected){play(kind,destination);return;}
  const a=source.getBoundingClientRect(),b=destination.getBoundingClientRect();
  if(!animated()){play(kind,destination);return;}
  const ghost=source.cloneNode(true);ghost.removeAttribute('id');for(const n of ghost.querySelectorAll('[id]'))n.removeAttribute('id');ghost.className='interaction-ghost';ghost.setAttribute('aria-hidden','true');Object.assign(ghost.style,{position:'fixed',left:`${a.x}px`,top:`${a.y}px`,width:`${a.width}px`,height:`${a.height}px`,margin:0,pointerEvents:'none',zIndex:150});document.body.append(ghost);
  const dx=b.x+b.width/2-a.x-a.width/2,dy=b.y+b.height/2-a.y-a.height/2;
  ghost.animate([{transform:'translate(0,0) scale(1)',opacity:.8},{transform:`translate(${dx}px,${dy}px) scale(.12)`,opacity:0}],{duration:390,easing:'cubic-bezier(.45,0,.65,1)'}).finished.then(()=>{ghost.remove();play(kind,destination);},()=>ghost.remove());
 }
 return {play,move,cleanup};
}
