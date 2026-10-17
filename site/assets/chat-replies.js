// A local scene conversation. No network request or real messaging account.
const rules=[
  {key:'photo',test:/图片|照片|风景|相片|photo|image/i,kind:'photo',texts:['这张是云下的牧场，羊群就在草地上。','照片发你了，留意远山和湖面的倒影。']},
  {key:'video',test:/视频|影片|电影|录像|video|movie/i,kind:'video',texts:['把屏幕夹子的实际操作演示发你，打开就能播放。','这段短片发你，慢慢看。','这段宣传视频在这里，可以随手夹在旁边。']},
  {key:'pdf',test:/pdf|手记/i,kind:'document',texts:['旅行手记整理成 PDF 了，发你看看。','这份 PDF 里有沿途的记录。','文稿在这里，翻页看看后面的内容。']},
  {key:'word',test:/docx|word|计划|行程|安排|文档/i,kind:'word',texts:['把出行计划发你，时间和目的地都可以直接改。','这是可编辑的 Word 版本，一起完善行程吧。','文档在这里，改好后也能夹起来留在手边。']},
  {key:'code',test:/代码|swift|编程|code/i,kind:'code',texts:['小便笺的 Swift 代码在这里，可以打开编辑。','把这段代码发你，试着改改标题。','源码给你了，修改后可以保存成真实文件。']},
  {key:'folder',test:/文件夹|文件包|目录|folder/i,kind:'folder',texts:['相关材料放进同一个文件夹了。','给你完整的旅行文件夹，里面的文件都能打开。']},
  {key:'audio',test:/录音|音频|声音|audio/i,kind:'audio',texts:['这段录音也留给你，打开播放器就能听。','录音文件发你了，想用时夹在手边。']},
  {key:'archive',test:/压缩|zip|归档/i,kind:'archive',texts:['材料打包好了，给你 ZIP 原件。','整理后的压缩包在这里。']},
  {key:'web',test:/网页|网址|链接|下载|网站|link/i,kind:'web',texts:['下载和介绍都在这个网页里。','把网页发你，可以打开看看。']},
  {key:'thanks',test:/谢谢|感谢|thanks|thank you/i,texts:['不客气，喜欢就好。','好呀，慢慢看。','随时找我，一起把计划补充完整。']},
  {key:'greeting',test:/你好|嗨|早上好|晚上好|hello|^hi\b/i,texts:['嗨，刚整理好这次出行的照片。想先看照片、短片，还是行程？','你好呀，要不要看看湖边的照片？','在呢。可以把照片、视频或计划发给你。']},
  {key:'time',test:/几点|什么时候|时间|周六|出发/i,texts:['计划里约在周六 09:30 出发。你可以打开文档改成合适的时间。','时间可以一起商量，先在出行计划里记下来吧。']},
  {key:'weather',test:/天气|下雨|晴天|温度/i,texts:['出发前再看看当地预报吧，记得带件外套。','晴天适合拍照，雨天也可以找间小店写手记。']},
];
const defaults=['记下了。要不要看看照片，或者一起改改行程？','好呀，我们把想法放进计划里。','我在听。想看照片、视频、文档或代码，告诉我就行。'];
export function chooseReply(text,counts=new Map(),attachmentKind){
  const matches=rules.filter(rule=>rule.test.test(text));
  const rule=matches[0]||{key:attachmentKind?'attachment':'default',texts:attachmentKind?['收到了，我先看看这份材料。','文件收到了，谢谢。','好，已经放进这次旅行的材料里。']:defaults};
  const n=counts.get(rule.key)||0;counts.set(rule.key,n+1);
  return [{text:rule.texts[n%rule.texts.length]},...matches.filter(rule=>rule.kind).map(rule=>({kind:rule.kind}))];
}
