export function bindSystemMenu({actions,canCapture}){
 const toggle=document.querySelector('[data-action=system-menu]'),menu=document.querySelector('#system-menu');
 const items=()=>[...menu.querySelectorAll('[role=menuitem]')];
 function close(refocus=false){menu.hidden=true;toggle.setAttribute('aria-expanded','false');if(refocus)toggle.focus();}
 function open(focus=false){document.dispatchEvent(new Event('clamp-close-context'));menu.hidden=false;toggle.setAttribute('aria-expanded','true');if(focus)items()[0]?.focus();}
 toggle.addEventListener('click',event=>{if(event.altKey||canCapture())return;event.stopPropagation();menu.hidden?open():close();});
 toggle.addEventListener('keydown',event=>{if(['ArrowDown','ArrowUp'].includes(event.key)&&!canCapture()){event.preventDefault();event.stopPropagation();open(true);if(event.key==='ArrowUp')items().at(-1)?.focus();}});
 menu.addEventListener('click',event=>{if(event.altKey||canCapture())return;const item=event.target.closest('[data-system-action]');if(!item)return;close();actions[item.dataset.systemAction]?.();});
 document.addEventListener('pointerdown',event=>{if(!menu.hidden&&!event.target.closest('#system-menu,[data-action=system-menu]'))close();},true);
 document.addEventListener('keydown',event=>{if(menu.hidden)return;if(event.key==='Escape'){event.preventDefault();event.stopPropagation();close(true);return;}if(event.key==='Tab'){close();return;}if(!['ArrowDown','ArrowUp','Home','End'].includes(event.key))return;event.preventDefault();const buttons=items(),index=buttons.indexOf(document.activeElement),next=event.key==='Home'?0:event.key==='End'?buttons.length-1:(index+(event.key==='ArrowUp'?-1:1)+buttons.length)%buttons.length;buttons[next]?.focus();});
 window.addEventListener('blur',()=>close());window.addEventListener('resize',()=>close());document.addEventListener('clamp-close-system-menu',()=>close());
 // Standard Mac preference shortcut, excluding the Option capture gesture.
 document.addEventListener('keydown',event=>{if((event.metaKey||event.ctrlKey)&&event.key===','&&!event.altKey){event.preventDefault();close();actions.settings?.();}});
 return {close,open};
}
