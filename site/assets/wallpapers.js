export const WALLPAPERS=[
 {id:'classic',name:'原色纸',path:'wallpaper-clip-minimal-v2.webp'},
 {id:'ivory',name:'暖白纸',path:'wallpapers/ivory.webp'},
 {id:'sage',name:'鼠尾草绿',path:'wallpapers/sage.webp'},
 {id:'blue',name:'雾蓝卷纸',path:'wallpapers/blue.webp'}
].map(item=>({...item,url:new URL(item.path,import.meta.url).href}));

export function createWallpapers({animated=()=>true,busy=()=>false,interval=300000}={}){
 const host=document.querySelector('.wallpaper'),layers=[0,1].map(()=>{const el=document.createElement('div');el.className='wallpaper-layer';host.append(el);return el;});
 const reduced=matchMedia('(prefers-reduced-motion: reduce)');
 let current='classic',automatic=!reduced.matches,active=0,loading=false,timer,pressed=false,bag=[];
 try{automatic=localStorage.getItem('clamp-wallpaper-auto')===null?automatic:localStorage.getItem('clamp-wallpaper-auto')==='true';current=WALLPAPERS.find(p=>p.id===localStorage.getItem('clamp-wallpaper'))?.id||current;}catch{}
 const saved=current;
 current='classic';layers[0].style.backgroundImage=`url("${WALLPAPERS[0].url}")`;layers[0].classList.add('visible');host.dataset.wallpaper=current;
 function notify(){document.dispatchEvent(new Event('clamp-wallpaper-change'));}
 function schedule(delay=interval){clearTimeout(timer);if(automatic&&!document.hidden)timer=setTimeout(()=>{if(pressed||busy())schedule(15000);else next();},delay);}
 async function select(id){
  if(loading)return false;const item=WALLPAPERS.find(p=>p.id===id);if(!item)return false;
  if(id===current){try{localStorage.setItem('clamp-wallpaper',id);}catch{}notify();schedule();return true;}loading=true;clearTimeout(timer);
  try{
   const image=new Image();image.src=item.url;await image.decode();
   const nextLayer=1-active,fade=animated()&&!reduced.matches;
   host.style.backgroundImage=layers[active].style.backgroundImage;host.classList.toggle('wallpaper-still',!fade);layers[nextLayer].style.backgroundImage=`url("${item.url}")`;
   layers[nextLayer].classList.add('visible');layers[active].classList.remove('visible');active=nextLayer;current=id;host.dataset.wallpaper=id;
   try{localStorage.setItem('clamp-wallpaper',id);}catch{}notify();
   if(fade)await new Promise(resolve=>setTimeout(resolve,1200));
   return true;
  }catch{return false;}finally{loading=false;schedule();}
 }
 async function next(){
  if(loading)return false;
  bag=bag.filter(id=>id!==current);
  if(!bag.length){bag=WALLPAPERS.map(p=>p.id).filter(id=>id!==current);for(let i=bag.length-1;i>0;i--){const j=Math.floor(Math.random()*(i+1));[bag[i],bag[j]]=[bag[j],bag[i]];}}
  return select(bag.pop());
 }
 function setAutomatic(value){automatic=!!value;try{localStorage.setItem('clamp-wallpaper-auto',String(automatic));}catch{}schedule();notify();}
 document.addEventListener('visibilitychange',()=>schedule());
 document.addEventListener('pointerdown',()=>{pressed=true;},true);
 document.addEventListener('pointerup',()=>{pressed=false;},true);
 document.addEventListener('pointercancel',()=>{pressed=false;},true);
 window.addEventListener('blur',()=>{pressed=false;});
 window.addEventListener('pagehide',()=>clearTimeout(timer));
 window.addEventListener('pageshow',()=>schedule());
 // A new visit starts with another random sheet; fixed choices survive reload.
 if(automatic){const choices=WALLPAPERS.filter(p=>p.id!==saved);select(choices[Math.floor(Math.random()*choices.length)].id);}else select(saved);
 schedule();
 return {next,select,setAutomatic,get current(){return current;},get automatic(){return automatic;}};
}
