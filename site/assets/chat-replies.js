// A local preset assistant. Messages and files never go to a real messaging account.
const rules=[
 {key:'help',test:/怎么用|如何用|如何夹|教程|上手|帮助|使用方法/i,kind:'document',texts:['按住 Option，让鼠标变成夹子；瞄准内容，按下、拖走、松手。靠边收起，停留展开。快速上手 PDF 发你，边看边练。','先夹一句话试试，再夹一张照片。拖住金属夹可以移动，点纸面复制；下面这份指南有完整步骤。']},
 {key:'types',test:/支持什么|哪些类型|能夹什么|支持哪些|文件类型/i,texts:['可以试试文字、照片、PDF、Word、网页、代码、文件夹、音频、视频、ZIP 和 JSON 数据。Mac 应用还支持把夹项组成收纳夹。桌面上的文件都是真实样本。','这个桌面准备了各类真实文件。文稿能翻页，Word 和代码能编辑；照片和视频使用你看到的实际原件。告诉我要哪一类，我发你。']},
 {key:'copy',test:/怎么复制|如何复制|复制|拖出|粘贴/i,texts:['点夹住的纸面会复制；再到网页访达粘贴，或拖到信息窗口。拖出文件会带上实际文件字节；系统剪贴板能力取决于浏览器。','抓夹子移动，拖内容复制。它们是两个不同的操作区：夹子在上方，纸张或图片是内容。']},
 {key:'undo',test:/撤销|误删|找回|恢复|废纸篓/i,texts:['把图标拖到废纸篓后，可以点击底部提示里的“撤销”；也可以按 Command Z，或打开废纸篓放回。刷新会恢复桌面演示文件。','误删了可以撤销。左上夹子菜单里还有“恢复桌面文件”，编辑好的文稿与代码仍然保留。']},
 {key:'save',test:/怎么保存|如何保存|保存在哪|自动保存/i,texts:['Word 与代码修改后会自动保存到当前浏览器，也可以点击保存或按 Command S。想留到电脑上，点击下载获得实际文件。','修改会保存到这个网页桌面；下载才会把副本留到你的电脑。备忘录右上方也会显示保存状态。']},
 {key:'photo',test:/图片|照片|风景|相片|photo|image/i,kind:'photo',texts:['实拍牧场照片发你。双击打开大图，或按住 Option 夹在旁边。','这次是实拍湖泊。你可以移动夹子、靠边收起，也可以拖出原图。']},
 {key:'video',test:/视频|影片|电影|录像|演示视频|video|movie/i,kind:'video',texts:['这段是屏幕夹子在真实 Mac 上的操作录屏，带分段字幕和下载地址。打开播放看看。','宣传视频发你了。可以暂停、拖动进度，也能像其他文件一样夹起来。']},
 {key:'pdf',test:/pdf|指南|说明书/i,kind:'document',texts:['三页快速上手指南发你：夹取、阅读取用、靠边收纳。打开后可以逐页查看。','这份 PDF 使用实际操作截图。边读边练，试试夹起它并翻到下一页。']},
 {key:'word',test:/docx|word|计划|安排|文档|文稿/i,kind:'word',texts:['可编辑的《我的桌面收纳计划》给你。打开后点“编辑”，写下自己的目标，再保存。','这份 Word 是练习用的收纳计划。把工作场景和资料位置改一改，再夹到手边。']},
 {key:'code',test:/代码|swift|编程|code/i,kind:'code',texts:['这是一个完整的 SwiftUI 便笺小示例。网页里能编辑和下载；运行需要在 Mac 的 SwiftUI 项目中完成。','QuickNote.swift 发你。先改便笺的那句话，保存后再夹起，预览也会跟着更新。']},
 {key:'folder',test:/文件夹|文件包|目录|folder/i,kind:'folder',texts:['入门资料放在这个文件夹里：指南、计划、实拍照片、代码和讲解。每个文件都能打开或夹取。','完整的入门资料文件夹发你，里面不是画出来的空图标，都是可使用的文件。']},
 {key:'audio',test:/录音|音频|声音|讲解|audio/i,kind:'audio',texts:['中文操作讲解发你，约半分钟。这是系统合成语音，文字稿也包含在素材包中。','这段音频介绍夹取、收起和展开。打开播放器可以暂停或拖动进度。']},
 {key:'archive',test:/素材包|压缩|zip|归档|打包/i,kind:'archive',texts:['入门素材已经打包成 ZIP。下载解压后，可以在真实 Mac 应用里继续练习。','演示素材包给你，里面包含指南、练习文稿、照片和代码。']},
 {key:'data',test:/json|数据|清单|配置/i,kind:'file',texts:['这份 JSON 展示阅读与写作的资料清单，便于查看和复制。它是示例数据，不是应用导入格式。','整理示例发你。打开后可以直接阅读格式化的 JSON 内容。']},
 {key:'web',test:/网页|网址|链接|下载|网站|link/i,kind:'web',texts:['介绍和 Mac 版下载都在这个网页里，也能查看版本记录与实际操作视频。','官网链接发你。上方有下载入口，下方可以看宣传视频和使用截图。']},
 {key:'thanks',test:/谢谢|感谢|thanks|thank you/i,texts:['不客气，继续随手试试。','好呀，喜欢的内容就夹在手边。']},
 {key:'greeting',test:/你好|嗨|hello|^hi\b/i,texts:['你好，我是这个桌面的夹子助手。可以问我怎么用、支持什么，或让我发指南、代码和素材包。','你好，想先看操作视频，还是直接夹一句话试试？']},
];
const defaults=['可以问我“怎么用”或“支持什么”，也可以指定要 PDF、Word、照片、视频或素材包。','我可以发送操作说明和实际文件。试试“发我指南”或“发我素材包”。'];
export function chooseReply(text,counts=new Map(),attachmentKind){
 const matches=rules.filter(rule=>rule.test.test(text)),rule=matches[0]||{key:attachmentKind?'attachment':'default',texts:attachmentKind?['文件收到了，已留在这段本地演示会话里。','收到了。你可以继续夹取、打开或把它放进资料夹。']:defaults};
 const n=counts.get(rule.key)||0;counts.set(rule.key,n+1);
 return [{text:rule.texts[n%rule.texts.length]},...matches.filter(rule=>rule.kind).filter((rule,i,all)=>all.findIndex(other=>other.kind===rule.kind)===i).map(rule=>({kind:rule.kind}))];
}
