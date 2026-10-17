"""Preserve the supplied desktop recording; add captions below the full frame."""
from pathlib import Path
from PIL import Image
import subprocess,imageio_ffmpeg,json
import argparse
parser=argparse.ArgumentParser(description='Prepare user-provided media and burn timed promotional captions. Requires Pillow and imageio-ffmpeg.')
parser.add_argument('--video',type=Path,required=True)
parser.add_argument('--photo',type=Path,required=True)
parser.add_argument('--secondary-photo',type=Path,required=True)
args=parser.parse_args()
root=Path(__file__).resolve().parents[2];out=root/'site/media-source/promotional';files=root/'site/assets/files'
out.mkdir(parents=True,exist_ok=True)
photo=args.photo;meadow=args.secondary_photo
for src,name,fmt in [(photo,'山间湖泊.png','PNG'),(meadow,'云下牧场.jpg','JPEG')]:
 im=Image.open(src).convert('RGB');im.thumbnail((1440,1440));im.save(files/name,fmt,**({'optimize':True} if fmt=='PNG' else {'quality':90,'optimize':True}))
segments=[
(0,5,'把灵感，夹在手边。','屏幕夹子 · macOS 原生实际操作演示'),
(5,12,'按住 Option，鼠标变成夹子','瞄准内容，夹住后随手放在屏幕边缘'),
(12,20,'想用时，轻轻展开','文字与视频，都有各自的真实形态'),
(20,28,'文稿留在眼前','夹住 Word 和代码，边看边用'),
(28,38,'PDF，也能随手翻阅','展开文稿，按页查看需要的内容'),
(38,46,'零散材料，逐一收好','压缩包、普通文件与便笺，保持各自的样子'),
(46,56,'链接和文件夹，一起夹住','把相关资料留在手边，继续眼前的工作'),
(56,65,'照片，保留原来的模样','从桌面夹起，在需要的位置展开'),
(65,76,'展开阅读，收起让出空间','随内容保留预览与原文件'),
(76,86,'每种内容，都有自己的触感','文稿、文件与收纳袋，自然地夹取和放置'),
(86,96,'跨窗口，也能留在手边','切换到浏览器，夹住的资料依然可见'),
(96,104,'从桌面，到网页里的桌面','在官网亲手试试，再把夹子带回 Mac'),
(104,109,'把灵感，夹在手边。','clamp.musefilm.top  ·  下载 Mac 版')]
(out/'captions.json').write_text(json.dumps(segments,ensure_ascii=False,indent=2)+'\n')
def ass_time(t):return f'{int(t)//3600}:{int(t)//60%60:02}:{int(t)%60:02}.00'
def srt_time(t):return f'{int(t)//3600:02}:{int(t)//60%60:02}:{int(t)%60:02},000'
(out/'屏幕夹子-宣传字幕.srt').write_text('\n\n'.join(f'{i+1}\n{srt_time(a)} --> {srt_time(b)}\n{title}\n{detail}' for i,(a,b,title,detail) in enumerate(segments))+'\n')
(out/'屏幕夹子-宣传字幕.vtt').write_text('WEBVTT\n\n'+'\n\n'.join(f'{srt_time(a).replace(",",".")} --> {srt_time(b).replace(",",".")}\n{title}\n{detail}' for a,b,title,detail in segments)+'\n')
ass='''[Script Info]
ScriptType: v4.00+
PlayResX: 1280
PlayResY: 848
ScaledBorderAndShadow: yes
[V4+ Styles]
Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
Style: Title,Hiragino Sans GB,30,&H00F0F3ED,&H00FFFFFF,&H00000000,&H00000000,-1,0,0,0,100,100,0,0,1,0,0,5,20,20,0,1
Style: Detail,Hiragino Sans GB,18,&H00B5C5B1,&H00FFFFFF,&H00000000,&H00000000,0,0,0,0,100,100,0,0,1,0,0,5,20,20,0,1
Style: Brand,Hiragino Sans GB,23,&H00F0F3ED,&H00FFFFFF,&H00000000,&H00000000,-1,0,0,0,100,100,0,0,1,0,0,4,20,20,0,1
[Events]
Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
Dialogue: 0,0:00:00.00,0:01:49.00,Brand,,0,0,0,,{\\pos(32,771)}屏幕夹子
Dialogue: 0,0:00:00.00,0:01:49.00,Detail,,0,0,0,,{\\an4\\pos(32,803)\\fs12\\fsp1.6}CLAMP EVERYTHING
'''
for a,b,title,detail in segments:
 for style,y,text in [('Title',765,title),('Detail',809,detail)]:ass+=f'Dialogue: 1,{ass_time(a)},{ass_time(b)},{style},,0,0,0,,{{\\pos(760,{y})\\fad(220,180)}}{text}\n'
(out/'captions.ass').write_text(ass)
f=imageio_ffmpeg.get_ffmpeg_exe();v=args.video
cmd=[f,'-hide_banner','-loglevel','warning','-i',str(v),'-vf',f"pad=1280:848:0:0:color=0x1c2824,drawbox=x=228:y=752:w=1:h=64:color=0x4b6156:t=fill,ass={out/'captions.ass'}",'-c:v','libx264','-preset','medium','-crf','25','-pix_fmt','yuv420p','-c:a','aac','-b:a','96k','-map_metadata','-1','-movflags','+faststart','-y',str(files/'屏幕夹子-实际操作演示.mov')]
print('Encoding original 109-second recording with timed captions...',flush=True)
subprocess.run(cmd,check=True)
subprocess.run([f,'-hide_banner','-loglevel','error','-ss','32','-i',str(files/'屏幕夹子-实际操作演示.mov'),'-frames:v','1','-y',str(out/'review-frame.jpg')],check=True)
