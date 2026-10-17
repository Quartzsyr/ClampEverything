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
types = {'.json':'application/json', '.jpg':'image/jpeg', '.png':'image/png', '.pdf':'application/pdf', '.docx':'application/vnd.openxmlformats-officedocument.wordprocessingml.document', '.txt':'text/plain', '.swift':'text/plain', '.html':'text/html', '.wav':'audio/wav', '.mov':'video/quicktime', '.zip':'application/zip', '.dat':'application/octet-stream'}
entries = []
for name in dict.fromkeys(item['file'] for item in [*manifest['items'], *manifest.get('extraItems', [])]):
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

word = files / '我的桌面收纳计划.docx'
with zipfile.ZipFile(word) as archive:
    doc = ET.fromstring(archive.read('word/document.xml'))
ns = {'w':'http://schemas.openxmlformats.org/wordprocessingml/2006/main'}
# Match file-editors.js's OOXML model from the first paint. Replacing an
# approximate plain preview after parsing used to shift text under the cursor.
def size_of(node):
    size = node.find('.//w:sz', ns)
    return float(size.get('{'+ns['w']+'}val', 36))/2 if size is not None else 18

def is_enabled(node, tag):
    item = node.find('.//w:'+tag, ns)
    return item is not None and item.get('{'+ns['w']+'}val') not in ('0', 'false', 'off')

paragraphs = []
for paragraph in doc.findall('.//w:body/w:p', ns):
    rendered = []
    for run in paragraph.findall('.//w:r', ns):
        text = ''.join(html.escape(child.text or '') if child.tag.endswith('}t') else '<br>' if child.tag.endswith('}br') else '\t' if child.tag.endswith('}tab') else '' for child in run)
        bold, italic = is_enabled(run, 'b'), is_enabled(run, 'i')
        rendered.append(f'<span data-word-size="{size_of(run):g}">'+('<b>' if bold else '')+('<i>' if italic else '')+text+('</i>' if italic else '')+('</b>' if bold else '')+'</span>')
    size = size_of(paragraph)
    heading = ' class="word-heading"' if size >= 24 else ''
    paragraphs.append(f'<p data-word-size="{size:g}"{heading}>'+(''.join(rendered) or '<br>')+'</p>')
body = ''.join(paragraphs)
preview = '<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>我的桌面收纳计划.docx</title><style>body{margin:0;padding:24px;background:#dfe4dc;color:#353d34;font:14px/1.85 system-ui}main{box-sizing:border-box;margin:auto;max-width:600px;padding:38px;background:white;box-shadow:0 3px 15px #3c4c392b;overflow-wrap:anywhere}p{margin:0;min-height:1.85em;white-space:pre-wrap}.word-heading{font-size:22px;font-weight:600}</style><main>' + body + '</main></html>'
(files / '我的桌面收纳计划.preview.html').write_text(preview)
archives = {}
for entry in entries:
    if entry['name'].endswith('.zip'):
        with zipfile.ZipFile(files / entry['name']) as archive:
            archives[entry['path']] = [dict(name=i.filename, size=i.file_size, directory=i.is_dir()) for i in archive.infolist()]
catalog = dict(archives=archives, files=entries, folders=[dict(name='屏幕夹子入门资料', children=[dict(name=p.name, path='../files/屏幕夹子入门资料/'+p.name) for p in sorted((files/'屏幕夹子入门资料').iterdir()) if p.is_file()])], previews={'note':dict(text=(root/'assets/native'/next(item['file'] for item in manifest['items'] if item['kind']=='note')).read_text()), 'word':dict(path='../files/我的桌面收纳计划.preview.html', sourceSHA256=hashlib.sha256(word.read_bytes()).hexdigest())})
(files / 'catalog.json').write_text(json.dumps(catalog, ensure_ascii=False, indent=2)+'\n')
