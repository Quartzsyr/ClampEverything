// JSZip 3.10.1 (MIT) reads the actual OOXML package and preserves its other parts.
// https://stuk.github.io/jszip/documentation/api_jszip/load_async.html
import './vendor/jszip/jszip.min.js';
const W='http://schemas.openxmlformats.org/wordprocessingml/2006/main';
const esc=value=>String(value).replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const elements=(root,tag)=>[...root.getElementsByTagNameNS(W,tag)];
const attr=(node,key)=>node?.getAttributeNS(W,key);
const enabled=node=>node&&!['0','false','off'].includes(attr(node,'val'));
export async function readWord(file){
  const zip=await window.JSZip.loadAsync(await file.arrayBuffer(),{checkCRC32:true});
  const xml=await zip.file('word/document.xml').async('string'),document=new DOMParser().parseFromString(xml,'application/xml');
  if(document.querySelector('parsererror'))throw new Error('DOCX 正文格式错误');
  const body=elements(document,'body')[0],paragraphs=[...body.children].filter(p=>p.localName==='p');
  const html=paragraphs.map(p=>{
    const runs=elements(p,'r').map(run=>{
      const size=Number(attr(elements(run,'sz')[0],'val'))/2||18,b=enabled(elements(run,'b')[0]),i=enabled(elements(run,'i')[0]);
      const text=[...run.children].filter(n=>['t','br','tab'].includes(n.localName)).map(n=>n.localName==='br'?'<br>':n.localName==='tab'?'\t':esc(n.textContent)).join('');
      return `<span data-word-size="${size}">${b?'<b>':''}${i?'<i>':''}${text}${i?'</i>':''}${b?'</b>':''}</span>`;
    }).join('');
    const size=Number(attr(elements(p,'sz')[0],'val'))/2||18;
    return `<p data-word-size="${size}"${size>=24?' class="word-heading"':''}>${runs||'<br>'}</p>`;
  }).join('');
  return {zip,document,body,html};
}
function blocks(root){return [...root.childNodes].flatMap(n=>n.nodeType===3?(n.textContent?[{node:n,size:18}]:[]):[{node:n,size:Number(n.dataset?.wordSize)||(n.matches?.('h1')?28:n.matches?.('h2')?24:18)}]);}
function runs(node,style={size:18,bold:false,italic:false}){
  if(node.nodeType===3)return [{text:node.textContent,...style}];
  if(node.nodeType!==1)return [];
  const weight=node.style.fontWeight,italic=node.style.fontStyle;
  const next={size:Number(node.dataset.wordSize)||style.size,bold:weight?weight==='bold'||Number(weight)>=600:style.bold||node.classList.contains('word-heading')||/^(B|STRONG|H1|H2)$/.test(node.tagName),italic:italic?italic==='italic':style.italic||/^(I|EM)$/.test(node.tagName)};
  if(node.tagName==='BR')return [{text:'\n',...next}];
  return [...node.childNodes].flatMap(n=>runs(n,next));
}
export async function writeWord(model,root,name){
  const document=model.document.cloneNode(true),body=elements(document,'body')[0],section=[...body.children].find(n=>n.localName==='sectPr')?.cloneNode(true);
  body.replaceChildren();
  for(const {node,size} of blocks(root)){
    const p=document.createElementNS(W,'w:p');
    for(const run of runs(node,{size,bold:false,italic:false})){
      const r=document.createElementNS(W,'w:r'),properties=document.createElementNS(W,'w:rPr');
      const font=document.createElementNS(W,'w:rFonts');font.setAttributeNS(W,'w:ascii','Helvetica Neue');font.setAttributeNS(W,'w:hAnsi','Helvetica Neue');properties.append(font);
      const sz=document.createElementNS(W,'w:sz');sz.setAttributeNS(W,'w:val',String(Math.round(run.size*2)));properties.append(sz);
      if(run.bold)properties.append(document.createElementNS(W,'w:b'));if(run.italic)properties.append(document.createElementNS(W,'w:i'));
      r.append(properties);
      run.text.split('\n').forEach((line,index)=>{if(index)r.append(document.createElementNS(W,'w:br'));const t=document.createElementNS(W,'w:t');t.setAttributeNS('http://www.w3.org/XML/1998/namespace','xml:space','preserve');t.textContent=line;r.append(t);});p.append(r);
    }
    if(!p.children.length)p.append(document.createElementNS(W,'w:r'));body.append(p);
  }
  if(!body.children.length)body.append(document.createElementNS(W,'w:p'));
  if(section)body.append(section);
  // Clone the package so an abandoned/stale save cannot mutate the source model.
  const zip=model.zip.clone();zip.file('word/document.xml',new XMLSerializer().serializeToString(document));
  const bytes=await zip.generateAsync({type:'uint8array',compression:'DEFLATE',compressionOptions:{level:6}});
  return new File([bytes],name,{type:'application/vnd.openxmlformats-officedocument.wordprocessingml.document'});
}
function wordPages(root){
  const pages=[];let context,y;
  function page(){const canvas=document.createElement('canvas');canvas.width=600;canvas.height=800;context=canvas.getContext('2d');context.fillStyle='#fffefb';context.fillRect(0,0,600,800);context.textBaseline='top';context.fillStyle='#383a36';y=48;pages.push(canvas);}
  page();
  for(const {node,size} of blocks(root)){
    let x=48;
    const list=runs(node,{size,bold:false,italic:false});const lineHeight=Math.max(25,...list.map(r=>r.size*1.4));
    if(y+lineHeight>752&&pages.length<24)page();
    for(const run of list){context.font=`${run.italic?'italic ':''}${run.bold?'600 ':''}${run.size}px -apple-system, BlinkMacSystemFont, sans-serif`;
      for(const char of run.text){const width=context.measureText(char).width;if(char==='\n'||x+width>552){x=48;y+=lineHeight;if(y+lineHeight>752){if(pages.length>=24)return pages.map(p=>p.toDataURL('image/png'));const font=context.font;page();context.font=font;}if(char==='\n')continue;}context.fillText(char,x,y);x+=width;}
    }
    y+=lineHeight+5;
  }
  return pages.map(p=>p.toDataURL('image/png'));
}
function codePage(text){
  const canvas=document.createElement('canvas');canvas.width=592;canvas.height=440;const c=canvas.getContext('2d');c.scale(2,2);c.font='10px ui-monospace, SFMono-Regular, Menlo, monospace';c.textBaseline='top';
  text.split('\n').slice(0,15).forEach((line,index)=>{c.fillStyle='#a5aaa0';c.fillText(String(index+1),8,12+index*14);c.fillStyle='#3b4841';c.save();c.beginPath();c.rect(30,0,254,220);c.clip();c.fillText(line.replace(/\t/g,'    '),31,12+index*14);c.restore();});return canvas.toDataURL('image/png');
}
export function editorToolbar(kind){return `<div class="editor-toolbar" data-editor-toolbar>${kind==='word'?'<select data-word-style aria-label="段落样式"><option value="18">正文</option><option value="28">标题</option><option value="24">小标题</option></select><button data-format="bold" aria-label="粗体"><b>B</b></button><button data-format="italic" aria-label="斜体"><i>I</i></button><button data-format="undo" aria-label="撤销">↶</button><button data-format="redo" aria-label="重做">↷</button>':'<span class="code-language">Swift</span>'}<span class="editor-save-state" role="status">${kind==='word'?'点击编辑以修改正文':'正在读取文件…'}</span>${kind==='word'?'<button data-toggle-word-edit disabled>编辑</button>':''}<button data-save-editor disabled aria-label="保存文件">保存 ⌘S</button><button data-editor-download data-download-file="${kind}" aria-label="下载编辑后的文件">下载 ↓</button></div>`;}
export function codeMarkup(){return '<div class="code-line-numbers" aria-hidden="true"></div><pre class="code-colors" aria-hidden="true"></pre><textarea class="code-input" disabled aria-label="Swift 代码编辑器" spellcheck="false" wrap="off" autocapitalize="off" autocomplete="off" autocorrect="off"></textarea><div class="code-position" aria-live="off"></div>';}
function coloredCode(text){return text.split(/(\/\/[^\n]*|"(?:[^"\\]|\\.)*"|\b(?:import|struct|let|var|func|return|if|else|true|false|nil|class|private|public|some|View|String|Int)\b)/g).map(token=>token.startsWith('//')?`<span class="syntax-comment">${esc(token)}</span>`:token.startsWith('"')?`<span class="syntax-string">${esc(token)}</span>`:/^(import|struct|let|var|func|return|if|else|true|false|nil|class|private|public|some|View|String|Int)$/.test(token)?`<span class="syntax-keyword">${token}</span>`:esc(token)).join('')+'\n';}
export async function attachEditor(record,{item,files,onSaved,onStatus,onFeedback=()=>{}}){
  const kind=item.kind,el=record.el,label=el.querySelector('.editor-save-state'),controller=new AbortController(),options={signal:controller.signal};
  let current=item,version=0,saved=0,pending=null,timer,root,doc,model,editing=kind==='code',disposed=false,savedSelection=null;
  const file=(await files.ensure(item)).file;
  if(kind==='code'){
    root=el.querySelector('.code-input');doc=document;root.value=await file.text();root.disabled=false;
    const sync=()=>{el.querySelector('.code-colors').innerHTML=coloredCode(root.value);el.querySelector('.code-line-numbers').textContent=root.value.split('\n').map((_,i)=>i+1).join('\n');position();};
    function position(){const before=root.value.slice(0,root.selectionStart);el.querySelector('.code-position').textContent=`第 ${before.split('\n').length} 行，第 ${before.split('\n').at(-1).length+1} 列`;}
    root.addEventListener('input',sync,options);root.addEventListener('click',position,options);root.addEventListener('keyup',position,options);
    root.addEventListener('scroll',()=>{for(const selector of ['.code-colors','.code-line-numbers']){const layer=el.querySelector(selector);layer.scrollTop=root.scrollTop;if(selector==='.code-colors')layer.scrollLeft=root.scrollLeft;}},options);
    root.addEventListener('keydown',e=>{if(e.key==='Tab'&&!e.metaKey&&!e.ctrlKey){e.preventDefault();const start=root.selectionStart,end=root.selectionEnd;root.setRangeText(e.shiftKey?'':'    ',start,end,'end');root.dispatchEvent(new Event('input',{bubbles:true}));}else if(e.key==='Enter'&&!e.metaKey&&!e.ctrlKey){const indent=root.value.slice(0,root.selectionStart).split('\n').at(-1).match(/^\s*/)[0];if(indent){e.preventDefault();root.setRangeText('\n'+indent,root.selectionStart,root.selectionEnd,'end');root.dispatchEvent(new Event('input',{bubbles:true}));}}},options);sync();
  }else{
    const frame=el.querySelector('iframe');
    if(!frame.contentDocument?.querySelector('main'))await new Promise((resolve,reject)=>{frame.addEventListener('load',resolve,{once:true,signal:controller.signal});controller.signal.addEventListener('abort',()=>reject(new Error('编辑器已关闭')),{once:true});});
    if(disposed||!el.isConnected)return;
    doc=frame.contentDocument;root=doc.querySelector('main');model=await readWord(file);root.innerHTML=item.editorHTML||model.html;
    // The static read-only preview emphasizes its first line. In an editor,
    // heading/normal state comes from the actual paragraph, including line one.
    for(const sheet of doc.styleSheets)try{for(let i=sheet.cssRules.length-1;i>=0;i--)if(sheet.cssRules[i].selectorText==='p:first-child')sheet.deleteRule(i);}catch{}
    const style=doc.createElement('style');style.textContent='main[contenteditable=true]{outline:2px solid #ccb87755;outline-offset:3px;cursor:text}p{margin:0;min-height:1.85em;white-space:pre-wrap}.word-heading{font-size:22px;font-weight:600}main{overflow-wrap:anywhere}';doc.head.append(style);
    root.setAttribute('role','textbox');root.setAttribute('aria-label','Word 文稿正文');root.setAttribute('aria-multiline','true');root.spellcheck=false;
    root.addEventListener('input',e=>{if(e.inputType!=='insertParagraph')return;const selection=doc.getSelection(),p=selection.anchorNode?.parentElement?.closest('p.word-heading');if(p&&p.textContent.trim()===''){p.classList.remove('word-heading');p.dataset.wordSize='18';for(const span of p.querySelectorAll('[data-word-size]'))span.dataset.wordSize='18';for(const b of p.querySelectorAll('b,strong'))b.replaceWith(...b.childNodes);}},options);
    root.addEventListener('paste',e=>{if(!editing)return;e.preventDefault();doc.execCommand('insertText',false,e.clipboardData.getData('text/plain'));},options);
  }
  if(disposed||!el.isConnected)return;
  label.textContent='已保存在此桌面';
  function dirty(){if(disposed)return;version++;label.textContent='正在保存…';clearTimeout(timer);timer=setTimeout(()=>flush().catch(fail),350);}
  function fail(error){label.textContent='保存失败，可重试';onFeedback('error');onStatus('未能保存文件',error.message,{kind:'error'});}
  async function flush(){
    clearTimeout(timer);if(pending){await pending;if(saved!==version)return flush();return current;}
    if(saved===version)return current;
    pending=(async()=>{while(saved!==version){
      const revision=version;let edited,previews,html,text;
      if(kind==='code'){text=root.value;edited=new File([text],file.name,{type:'text/plain;charset=utf-8'});previews=[codePage(text)];}
      else{const snapshot=root.cloneNode(true);html=snapshot.innerHTML;text=snapshot.textContent;edited=await writeWord(model,snapshot,file.name);previews=wordPages(snapshot);}
      if(revision!==version)continue;
      const next=await files.register(edited,item,{editorText:text,editorHTML:html,source:previews[0],previewPages:previews,left:`${kind}-blank-left.webp`,right:`${kind}-blank-right.webp`,pages:kind==='word'?previews.map(src=>({left:'word-blank-left.webp',right:'word-blank-right.webp',surfaceLeft:src,surfaceRight:src})):undefined});
      if(revision!==version)continue;if(disposed)return next;const persisted=await files.saveWorking(next);if(disposed)return next;if(revision!==version)continue;current=next;saved=revision;onSaved(next);label.textContent=persisted?'已保存在此桌面':'已保存在此会话';
    }return current;})();
    try{return await pending;}finally{pending=null;}
  }
  root.addEventListener('input',dirty,options);
  root.addEventListener('keydown',e=>{if((e.metaKey||e.ctrlKey)&&e.key.toLowerCase()==='s'){e.preventDefault();flush().catch(fail);}},options);
  const toolbar=el.querySelector('[data-editor-toolbar]');for(const button of toolbar.querySelectorAll('[data-toggle-word-edit],[data-save-editor]'))button.disabled=false;
  function rememberSelection(){const selection=doc.getSelection();if(selection?.rangeCount&&root.contains(selection.anchorNode)&&root.contains(selection.focusNode))savedSelection=selection.getRangeAt(0).cloneRange();}
  function restoreSelection(){root.focus();if(savedSelection&&root.contains(savedSelection.commonAncestorContainer)){const selection=doc.getSelection();selection.removeAllRanges();selection.addRange(savedSelection.cloneRange());}}
  function formatState(){if(kind==='word')rememberSelection();for(const button of toolbar.querySelectorAll('[data-format]')){button.disabled=!editing;if(['bold','italic'].includes(button.dataset.format))button.setAttribute('aria-pressed',String(editing&&doc.queryCommandState(button.dataset.format)));}if(kind==='word'){const paragraph=doc.getSelection()?.anchorNode?.parentElement?.closest('[data-word-size]');if(paragraph&&root.contains(paragraph)){const size=paragraph.dataset.wordSize,select=toolbar.querySelector('[data-word-style]');if(['18','24','28'].includes(size))select.value=size;}}}
  if(kind==='word'){doc.addEventListener('selectionchange',formatState,options);formatState();toolbar.querySelector('[data-word-style]').disabled=true;}
  toolbar.addEventListener('change',e=>{if(!e.target.matches('[data-word-style]')||!editing)return;const selection=doc.getSelection(),range=savedSelection||(selection.rangeCount?selection.getRangeAt(0):null),size=Number(e.target.value);
    for(const {node} of blocks(root)){if(node.nodeType!==1||range&&!range.intersectsNode(node))continue;node.dataset.wordSize=String(size);node.classList.toggle('word-heading',size>=24);node.style.fontSize=`${size===28?22:size===24?19:14}px`;node.style.fontWeight=size>=24?'600':'normal';for(const span of node.querySelectorAll('[data-word-size]'))span.dataset.wordSize=String(size);}
    dirty();restoreSelection();formatState();
  },options);
  // Keep selection in the document when using formatting controls.
  toolbar.addEventListener('pointerdown',e=>{if(e.target.closest('[data-format],[data-word-style]'))rememberSelection();if(e.target.closest('[data-format]'))e.preventDefault();},options);
  toolbar.addEventListener('click',async e=>{try{
    if(e.target.closest('[data-toggle-word-edit]')){editing=!editing;root.contentEditable=String(editing);e.target.closest('button').textContent=editing?'完成':'编辑';toolbar.querySelector('[data-word-style]').disabled=!editing;if(editing)root.focus();else await flush();formatState();}
    const format=e.target.closest('[data-format]');if(format&&editing){restoreSelection();doc.execCommand(format.dataset.format);rememberSelection();formatState();}
    if(e.target.closest('[data-save-editor]')){await flush();onFeedback('save');onStatus('已保存',file.name,{kind:'save'});}
    if(e.target.closest('[data-editor-download]')){await files.download(await flush());onFeedback('download');onStatus('已开始下载',file.name,{kind:'download'});}
  }catch(error){fail(error);}},options);
  return {flush,dispose:()=>{disposed=true;clearTimeout(timer);controller.abort();},get item(){return current;},get dirty(){return saved!==version;}};
}
