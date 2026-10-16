// Every source resolves to the bytes of an authored demo file. Native PNGs are
// thumbnails only: opening, downloading and drag-copying use this same File.
export class FileLibrary {
  constructor(nativeURL) { this.url = nativeURL; this.records = new Map(); this.failures = new Map(); }
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
    transfer.setData('text/uri-list', this.url(item.file));
    transfer.setData('text/plain', record.name);
    // Chromium's external file export convention, in addition to the File item.
    transfer.setData('DownloadURL', `${record.mime}:${record.name}:${this.url(item.file)}`);
    return true;
  }
  resolveDrag(transfer, items) {
    try {
      const {id,kind} = JSON.parse(transfer.getData('application/x-clamp-file'));
      const item = items.find(item => item.kind === kind && item.fileId === id);
      return this.find(id) && item;
    } catch { return null; }
  }
}
