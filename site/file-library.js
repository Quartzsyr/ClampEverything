// Every source resolves to the bytes of an authored demo file. Native PNGs are
// thumbnails only: opening, downloading and drag-copying use this same File.
export class FileLibrary {
  constructor(nativeURL) { this.url = nativeURL; this.records = new Map(); }
  async load(items) {
    const response = await fetch(new URL('./assets/files/catalog.json', import.meta.url));
    if (!response.ok) throw new Error('演示文件目录加载失败');
    this.catalog = await response.json();
    await Promise.all(this.catalog.files.map(async entry => {
      const response = await fetch(this.url(entry.path));
      if (!response.ok) throw new Error(`文件加载失败：${entry.name}`);
      const bytes = await response.arrayBuffer();
      const digest = Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256', bytes)), b => b.toString(16).padStart(2, '0')).join('');
      if (digest !== entry.sha256 || bytes.byteLength !== entry.size) throw new Error(`文件校验失败：${entry.name}`);
      const file = new File([bytes], entry.name, {type:entry.mime, lastModified:0});
      this.records.set(entry.path, {...entry, file, href:URL.createObjectURL(file)});
    }));
    for (const item of items) {
      const record = this.get(item);
      if (!record) throw new Error(`缺少原文件：${item.title}`);
      item.fileId = record.sha256;
    }
  }
  get(item) { return this.records.get(item.file); }
  find(id) { return [...this.records.values()].find(record => record.sha256 === id); }
  text(item) { return this.get(item).file.text(); }
  href(item) { return this.get(item).href; }
  download(item) {
    const record = this.get(item), link = document.createElement('a');
    link.href = record.href; link.download = record.name; link.click();
  }
  writeDrag(transfer, item) {
    const record = this.get(item);
    transfer.effectAllowed = 'copy';
    transfer.items.add(record.file);
    transfer.setData('application/x-clamp-file', JSON.stringify({id:record.sha256, kind:item.kind}));
    transfer.setData('text/uri-list', this.url(item.file));
    transfer.setData('text/plain', record.name);
    // Chromium's external file export convention, in addition to the File item.
    transfer.setData('DownloadURL', `${record.mime}:${record.name}:${this.url(item.file)}`);
  }
  resolveDrag(transfer, items) {
    try {
      const {id,kind} = JSON.parse(transfer.getData('application/x-clamp-file'));
      const item = items.find(item => item.kind === kind && item.fileId === id);
      return this.find(id) && item;
    } catch { return null; }
  }
}
