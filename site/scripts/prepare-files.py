"""Index the authored real files; derive Word's read-only HTML from its OOXML.

Run after changing fixtures or re-exporting the native app previews. No invented
document copy lives in the website's JS; the DOCX itself supplies every paragraph.
"""
from pathlib import Path
import hashlib
import html
import json
import zipfile
import xml.etree.ElementTree as ET

root = Path(__file__).resolve().parents[1]
files = root / 'assets/files'
manifest = json.loads((root / 'assets/native/manifest.json').read_text())
types = {'.png':'image/png', '.pdf':'application/pdf', '.docx':'application/vnd.openxmlformats-officedocument.wordprocessingml.document', '.txt':'text/plain', '.swift':'text/plain', '.html':'text/html', '.wav':'audio/wav', '.mov':'video/quicktime', '.zip':'application/zip', '.dat':'application/octet-stream'}
entries = []
for name in dict.fromkeys(item['file'] for item in manifest['items']):
    path = (root / 'assets/native' / name).resolve()
    data = path.read_bytes()
    entry = dict(path=name, name=path.name, size=len(data), mime=types[path.suffix], sha256=hashlib.sha256(data).hexdigest())
    # A CDN may inject scripts into text/html responses. Transport the exact
    # original bytes as binary; the normal HTML URL remains the live viewer.
    if path.suffix == '.html':
        companion = path.with_name(path.name + '.bin')
        companion.write_bytes(data)
        entry['bytesPath'] = name + '.bin'
    entries.append(entry)

word = files / '出行计划.docx'
with zipfile.ZipFile(word) as archive:
    doc = ET.fromstring(archive.read('word/document.xml'))
ns = {'w':'http://schemas.openxmlformats.org/wordprocessingml/2006/main'}
paragraphs = [''.join(p.itertext()) for p in doc.findall('.//w:body/w:p', ns)]
body = ''.join(f'<p>{html.escape(text) or "&nbsp;"}</p>' for text in paragraphs)
preview = '<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>出行计划.docx</title><style>body{margin:0;padding:24px;background:#dfe4dc;color:#353d34;font:14px/1.85 system-ui}main{box-sizing:border-box;margin:auto;max-width:600px;padding:38px;background:white;box-shadow:0 3px 15px #3c4c392b}p{margin:0;min-height:1.85em;white-space:pre-wrap}p:first-child{font-size:23px;font-weight:600}</style><main>' + body + '</main></html>'
(files / '出行计划.preview.html').write_text(preview)
archives = {}
for entry in entries:
    if entry['name'].endswith('.zip'):
        with zipfile.ZipFile(files / entry['name']) as archive:
            archives[entry['path']] = [dict(name=i.filename, size=i.file_size, directory=i.is_dir()) for i in archive.infolist()]
catalog = dict(archives=archives, files=entries, folders=[dict(name='周末旅行', children=[dict(name=p.name, path='../files/周末旅行/'+p.name) for p in sorted((files/'周末旅行').iterdir()) if p.is_file()])], previews={'word':dict(path='../files/出行计划.preview.html', sourceSHA256=hashlib.sha256(word.read_bytes()).hexdigest())})
(files / 'catalog.json').write_text(json.dumps(catalog, ensure_ascii=False, indent=2)+'\n')
