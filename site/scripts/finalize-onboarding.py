"""Restore extra-media descriptors after a scoped native full export."""
from pathlib import Path
import json,wave
root=Path(__file__).resolve().parents[1];p=root/'assets/native/manifest.json';m=json.loads(p.read_text());m['folderName']='屏幕夹子入门资料';m['contentVersion']='onboarding-20261017'
photo=next(i for i in m['items'] if i['kind']=='photo');photo.update(pixelWidth=1440,pixelHeight=960)
extra=dict(photo);extra.update(title='云下牧场.jpg',file='../files/云下牧场.jpg',source='../files/云下牧场.jpg',height=238)
for key,suffix in [('left','left'),('right','right'),('compactLeft','compact-left'),('compactRight','compact-right')]:extra[key]=f'photo-meadow-{suffix}.webp'
m['extraItems']=[extra]
next(i for i in m['items'] if i['kind']=='video').update(duration=109,pixelWidth=1280,pixelHeight=848)
with wave.open(str(root/'assets/files/夹取操作讲解.wav')) as audio:next(i for i in m['items'] if i['kind']=='audio')['duration']=audio.getnframes()/audio.getframerate()
p.write_text(json.dumps(m,ensure_ascii=False,indent=2)+'\n')
