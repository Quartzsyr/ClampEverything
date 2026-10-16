// Every source resolves to the bytes of an authored demo file. Native PNGs are
// thumbnails only: opening, downloading and drag-copying use this same File.
export class FileLibrary {
  constructor(nativeURL) { this.url = nativeURL; this.records = new Map(); this.failures = new Map(); this.localItems = new Map(); }
  async register(file,template,details={}) {
    const bytes=await file.arrayBuffer(),sha256=Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',bytes)),b=>b.toString(16).padStart(2,'0')).join('');
    const path=`local/${sha256}/${encodeURIComponent(file.name)}`,existing=this.localItems.get(path);
    if(existing)return Object.assign(existing,details);
    const item={...template,...details,file:path,fileId:sha256,local:true};
    this.records.set(path,{path,name:file.name,size:file.size,mime:file.type,sha256,file,href:URL.createObjectURL(file)});this.localItems.set(path,item);return item;
  }
  async database(){
    if(!globalThis.indexedDB)return null;
    this.dbPromise??=new Promise((resolve,reject)=>{const request=indexedDB.open('clamp-desktop-files',1);request.onupgradeneeded=()=>request.result.createObjectStore('working',{keyPath:'kind'});request.onsuccess=()=>resolve(request.result);request.onerror=()=>reject(request.error);});
    return this.dbPromise;
  }
  async saveWorking(item){
    try{const db=await this.database();if(!db)return false;const record=this.get(item),bytes=await record.file.arrayBuffer();
      // Store bytes, not a File-backed temporary path: WebKit can reject Blob
      // preparation even while ordinary ArrayBuffer transactions remain usable.
      await new Promise((resolve,reject)=>{const tx=db.transaction('working','readwrite');tx.objectStore('working').put({kind:item.kind,name:record.name,mime:record.mime,bytes,item});tx.oncomplete=resolve;tx.onerror=event=>reject(event.target.error||tx.error||new Error('本地存储写入失败'));});return true;
    }catch(error){this.storageError={name:error?.name,message:error?.message};return false;}
  }
  async restoreWorking(){
    try{const db=await this.database();if(!db)return [];
      const entries=await new Promise((resolve,reject)=>{const request=db.transaction('working').objectStore('working').getAll();request.onsuccess=()=>resolve(request.result);request.onerror=()=>reject(request.error);});
      return await Promise.all(entries.filter(e=>['note','word','code'].includes(e.kind)).map(e=>this.register(new File([e.bytes||e.blob],e.name,{type:e.mime}),e.item)));
    }catch{return [];}
  }
  async clearWorking(){try{const db=await this.database();if(db)await new Promise((resolve,reject)=>{const tx=db.transaction('working','readwrite');tx.objectStore('working').clear();tx.oncomplete=resolve;tx.onerror=event=>reject(event.target.error||tx.error||new Error('本地存储写入失败'));});}catch{}}
  async createText(text,template,name='新便笺.txt') {
    return this.register(new File([text],name,{type:'text/plain;charset=utf-8'}),template,{title:name.replace(/\.txt$/,''),textContent:text,left:'note-blank-left.webp',right:'note-blank-right.webp'});
  }
  async load(items) {
    const response = await fetch(new URL('./assets/files/catalog.json', import.meta.url),{cache:'no-store'});
    if (!response.ok) throw new Error('演示文件目录加载失败');
    this.catalog = await response.json();
    for(const entry of this.catalog.files)this.records.set(entry.path,{...entry,file:null,href:this.url(entry.path)});
    const results=await Promise.allSettled(this.catalog.files.map(entry=>this.read(entry)));
    results.forEach((result,index)=>{if(result.status==='rejected')this.failures.set(this.catalog.files[index].path,result.reason);});
    for (const item of items) {
      const record = this.get(item);
      if (!record) throw new Error(`缺少原文件：${item.title}`);
      item.fileId = record.sha256;
    }
  }
  async read(entry) {
    let error;
    for(let attempt=0;attempt<2;attempt++)try{
      const url=new URL(this.url(entry.bytesPath||entry.path));url.searchParams.set('v',entry.sha256.slice(0,16));
      const response=await fetch(url,{cache:'no-store',signal:AbortSignal.timeout(12000)});
      if(!response.ok)throw new Error(`文件加载失败：${entry.name}`);
      const bytes=await response.arrayBuffer();
      if(!globalThis.crypto?.subtle)throw new Error('请使用 HTTPS 打开网页');
      const digest=Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',bytes)),b=>b.toString(16).padStart(2,'0')).join('');
      if(digest!==entry.sha256||bytes.byteLength!==entry.size)throw new Error(`文件校验失败：${entry.name}`);
      const file=new File([bytes],entry.name,{type:entry.mime,lastModified:0}),record={...entry,file,href:URL.createObjectURL(file)};
      const old=this.records.get(entry.path);if(old?.file)URL.revokeObjectURL(old.href);
      this.records.set(entry.path,record);this.failures.delete(entry.path);return record;
    }catch(reason){error=reason;}
    throw error;
  }
  async ensure(item) { const record=this.get(item);if(!record)throw new Error('缺少原文件');return record.file?record:this.read(record); }
  get(item) { return this.records.get(item.file); }
  find(id) { return [...this.records.values()].find(record => record.sha256 === id); }
  async text(item) { return (await this.ensure(item)).file.text(); }
  href(item) { return this.get(item).href; }
  async download(item) {
    const record = await this.ensure(item), link = document.createElement('a');
    link.href = record.href; link.download = record.name; link.click();
  }
  writeDrag(transfer, item) {
    const record = this.get(item);
    if(!record?.file)return false;
    transfer.effectAllowed = 'copy';
    transfer.items.add(record.file);
    transfer.setData('application/x-clamp-file', JSON.stringify({id:record.sha256, kind:item.kind}));
    const href=item.local?record.href:this.url(item.file);
    transfer.setData('text/uri-list', href);
    transfer.setData('text/plain', record.name);
    // Chromium's external file export convention, in addition to the File item.
    transfer.setData('DownloadURL', `${record.mime}:${record.name}:${href}`);
    return true;
  }
  resolveDrag(transfer, items) {
    try {
      const {id,kind} = JSON.parse(transfer.getData('application/x-clamp-file'));
      const item = [...items,...this.localItems.values()].find(item => item.kind === kind && item.fileId === id);
      return this.find(id) && item;
    } catch { return null; }
  }
}
