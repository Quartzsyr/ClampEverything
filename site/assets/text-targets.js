// One hit test supplies both the native-style marker and the captured TXT.
// Same-origin document coordinates are projected back into the desktop viewport.
const contains=(r,x,y)=>x>=r.left&&x<=r.right&&y>=r.top&&y<=r.bottom;
const box=r=>({x:r.left,y:r.top,left:r.left,top:r.top,right:r.right,bottom:r.bottom,width:r.width,height:r.height});
function intersect(r,c){const left=Math.max(r.left,c.left),top=Math.max(r.top,c.top),right=Math.min(r.right,c.right),bottom=Math.min(r.bottom,c.bottom);return {x:left,y:top,left,top,right,bottom,width:right-left,height:bottom-top};}
function visibleRects(rects,element,frame){
  const doc=element.ownerDocument,win=doc.defaultView;
  let clip={left:0,top:0,right:win.innerWidth,bottom:win.innerHeight};
  for(let parent=element;parent&&parent!==doc.body;parent=parent.parentElement){if(/auto|scroll|hidden|clip/.test(win.getComputedStyle(parent).overflow))clip=intersect(clip,parent.getBoundingClientRect());}
  let regions=rects.map(r=>intersect(r,clip)).filter(r=>r.width>1&&r.height>1);
  if(frame){const f=frame.getBoundingClientRect(),sx=f.width/frame.clientWidth,sy=f.height/frame.clientHeight;
    regions=regions.map(r=>box({left:f.left+r.left*sx,top:f.top+r.top*sy,right:f.left+r.right*sx,bottom:f.top+r.bottom*sy,width:r.width*sx,height:r.height*sy}));
    for(let parent=frame.parentElement;parent&&parent!==document.body;parent=parent.parentElement){if(/auto|scroll|hidden|clip/.test(getComputedStyle(parent).overflow))regions=regions.map(r=>intersect(r,parent.getBoundingClientRect()));}
  }
  return regions.filter(r=>r.width>1&&r.height>1);
}
function rangeRects(range,el,frame){return visibleRects([...range.getClientRects()],el,frame);}
function inputRects(input,frame,selected){
  const doc=input.ownerDocument,style=doc.defaultView.getComputedStyle(input),r=input.getBoundingClientRect(),mirror=doc.createElement('div');
  for(const name of ['font','fontSize','fontFamily','fontWeight','fontStyle','lineHeight','letterSpacing','textAlign','textIndent','padding','border','boxSizing','tabSize','wordBreak','overflowWrap'])mirror.style[name]=style[name];
  Object.assign(mirror.style,{position:'fixed',left:`${r.left}px`,top:`${r.top}px`,width:`${r.width}px`,height:`${r.height}px`,margin:'0',opacity:'0',overflow:'hidden',pointerEvents:'none',whiteSpace:input.matches('textarea')?style.whiteSpace:'pre'});
  if(!input.matches('textarea'))mirror.style.lineHeight=`${input.clientHeight-parseFloat(style.paddingTop)-parseFloat(style.paddingBottom)}px`;
  mirror.textContent=input.value+'\u200b';doc.body.append(mirror);mirror.scrollTop=input.scrollTop;mirror.scrollLeft=input.scrollLeft;
  const range=doc.createRange();range.setStart(mirror.firstChild,selected?input.selectionStart:0);range.setEnd(mirror.firstChild,selected?input.selectionEnd:input.value.length);
  const regions=visibleRects([...range.getClientRects()],input,frame);mirror.remove();return regions;
}
function descriptor(element,text,regions,frame,key=element){
  if(!text.trim()||!regions.length)return null;
  const left=Math.min(...regions.map(r=>r.left)),top=Math.min(...regions.map(r=>r.top)),right=Math.max(...regions.map(r=>r.right)),bottom=Math.max(...regions.map(r=>r.bottom));
  return {element:frame?.parentElement||element,key,text,regions,bounds:{x:left,y:top,width:right-left,height:bottom-top}};
}
export function textTargetAt(x,y){
  let doc=document,frame=null,hit=doc.elementFromPoint(x,y),px=x,py=y;
  const candidate=hit?.matches('iframe')?hit:hit?.closest('.frame-source')?.querySelector('iframe');
  if(candidate){try{const inner=candidate.contentDocument;if(inner?.body){frame=candidate;const r=frame.getBoundingClientRect();px=(x-r.left)*frame.clientWidth/r.width;py=(y-r.top)*frame.clientHeight/r.height;doc=inner;hit=doc.elementFromPoint(px,py);}}catch{/* External pages retain whole-file capture. */}}
  if(!hit||hit.closest('script,style,svg,#demo-cursor,#target-glow,#flight-layer,[data-resize],[data-panel-resize]'))return null;
  if(hit.matches('input,textarea')){
    if(hit.matches('[type=checkbox],[type=range],[type=radio],[type=color]'))return null;
    const selected=hit.selectionStart!=null&&hit.selectionEnd>hit.selectionStart;
    // The code editor still exposes its Swift original; selecting a passage
    // explicitly takes that passage as text instead.
    if(hit.closest('.code-editor')&&!selected)return null;
    const text=selected?hit.value.slice(hit.selectionStart,hit.selectionEnd):hit.value;
    return descriptor(hit,text,inputRects(hit,frame,selected),frame);
  }
  const selection=doc.getSelection();
  if(selection&&!selection.isCollapsed&&selection.rangeCount){
    const range=selection.getRangeAt(0),anchor=range.commonAncestorContainer.nodeType===1?range.commonAncestorContainer:range.commonAncestorContainer.parentElement;
    const regions=rangeRects(range,anchor,frame);
    if(regions.some(r=>contains(r,x,y)))return descriptor(anchor,selection.toString(),regions,frame,anchor);
  }
  // Existing notes/messages retain their complete original TXT unless a range
  // is explicitly selected. Their per-line native marker is handled by glow.
  if(hit.closest('[data-source-kind=note]:not(.desktop-file):not(.finder-file):not(.message-attachment)'))return null;
  let caret;
  if(doc.caretPositionFromPoint){const p=doc.caretPositionFromPoint(px,py);if(p){caret=doc.createRange();caret.setStart(p.offsetNode,p.offset);caret.collapse(true);}}
  else caret=doc.caretRangeFromPoint?.(px,py);
  const node=caret?.startContainer;
  if(!node||node.nodeType!==3||!node.textContent.trim()||!hit.contains(node))return null;
  const glyph=doc.createRange();glyph.selectNodeContents(node);
  // Caret APIs also return the nearest text in blank gutters. Require a real
  // glyph line under the pointer so icons and paper margins remain file targets.
  if(![...glyph.getClientRects()].some(r=>contains(r,px,py)))return null;
  const parent=node.parentElement;
  const paragraph=parent.closest('p,h1,h2,h3,h4,h5,h6,figcaption,pre,td,th,.file-name,.window-title,.message-caption,.pdf-text-line');
  let root=paragraph||parent;
  if(root.matches('body,main,section,article,header,footer,nav,div')&&root.children.length)root=parent;
  const range=doc.createRange();range.selectNodeContents(root);
  const text=root.innerText??root.textContent;
  return descriptor(root,text,rangeRects(range,root,frame),frame);
}
