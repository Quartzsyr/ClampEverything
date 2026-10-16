# 屏幕夹子 · 一个可交互的 Mac 桌面

公开页面：https://quartzsyr.github.io/ClampEverything/

交互参考 [Tendedero](https://tendedero.app/) 将产品放进桌面使用场景的方式。页面打开后，文件已经摆在桌面上，信息和浏览器窗口也已经打开。浏览器直接展示屏幕夹子的介绍与下载页，首屏可点击下载 v1.7.16；这是可独立打开的真实 HTML 文件，不是截图。演示发生在使用过程中，没有「先选类型，再生成样本」的步骤。

## 桌面与应用逻辑

- 桌面直接放置 PDF、Word、视频、图片、文件夹、代码、录音、归档、文本及数据文件。普通鼠标单击选择、双击打开；按住 ⌥ Option（Windows / Linux 为 Alt）才变成夹子，按下内容并拖动，松开鼠标放置。
- 信息窗口里的文字直接读取实际 TXT 文件，收到的照片、PDF 与视频来自同一组真实文件。夹取后原消息与原附件保留。
- Dock 只有应用：访达、信息、Safari、备忘录、QuickTime、屏幕夹子和废纸篓。它打开、激活或恢复应用窗口，不选择夹取类型。
- 所有应用窗口支持拖动标题栏移动，从四边与四角调整大小，以及关闭、最小化和缩放。设置、帮助与应用信息面板同样支持移动、缩放，内容独立滚动。关闭窗口保留应用的运行状态；Dock 再次点击可打开窗口。
- 访达可以进入文件夹、返回桌面。文件右键可打开、快速查看、复制、在访达中显示、下载原文件（文件夹下载为实际 ZIP）。桌面空白区域可拖动选择文件。
- 播放器读取真实 MOV / WAV，播放控件和夹取画面分别响应。
- 拖金属夹移动已夹物件；靠边放置收起，悬停展开。拖到废纸篓可移除夹项，原文件保留；废纸篓中可放回。
- 点击已夹内容复制，拖出内容可复制到访达或信息。放入信息先成为草稿，点击发送后才进入会话。
- 没有自动播放或自动夹取。松开 Option 恢复普通鼠标；放下前松开 Option、Esc、右键或窗口失焦会取消当前夹取。一次夹取后需要松开再按 Option 才能重新开始。桌面窗口、Dock 和菜单本身不成为夹取内容。

## 原生素材

`assets/files/` 保存专门制作的真实 PNG、TXT、三页 PDF、三页 DOCX、Swift、HTML、WAV、MOV、DAT、ZIP 及示例文件夹。`catalog.json` 记录每个原文件的 MIME、大小与 SHA-256，启动时先加载并校验，再创建浏览器 `File` 对象。桌面、聊天附件、夹项与拖出副本引用相同文件身份；拖出携带原文件字节，右键可下载原件。它们先由桌面端 `ClipStore.importFiles` 读取，再由实际 `CardSurface` / `ItemBody` / `DocumentPages` / `PhotoBody` 绘制。

`assets/native/` 保存这些原生组件的透明离屏渲染。文字字体、文件图标、目录、纸面磨损、金属夹及夹口阴影来自原生组件。`provenance.json` 记录源文件摘要，`manifest.json` 记录原文件与图像的对应关系。

- 原生组装图为 Retina 2×，四周有 32 点透明安全区。
- 悬点为左侧 `(44,26)`、右侧 `(width−44,26)`；夹子与内容一起旋转，钉子固定。
- 收起图逻辑尺寸 64×60，已包含原生 ±105° 姿态。
- PDF / DOCX 各三页均来自原文件；翻页使用单独的原生纸面，金属夹保持不动。
- 鼠标夹子三态由 `ImageGenCursorClip` 导出。

应用场景的窗口由网页实现，夹取后呈现的物件使用原生渲染。打开 PDF 使用本地打包的 [Mozilla PDF.js](https://mozilla.github.io/pdf.js/examples/) 5.6.205 直接解析文件字节并渲染所有页面；Word 的可滚动预览由 `scripts/prepare-files.py` 从 DOCX 的 OOXML 正文导出，保存原件摘要。Safari 加载真实 HTML 下载页，由页面自身响应式布局适应窗口宽度；图片直接使用 PNG 原件，音视频可播放，文本和代码读取原文件，压缩包展示真实 ZIP 条目，文件夹条目来自实际目录。

网页内部维护场景文件和剪贴板；普通文本、代码和图片同时尝试浏览器系统剪贴板。它不访问用户个人文件或真实聊天账户。所有文件与消息都是仓库中的固定素材。

壁纸由内置 image_gen 生成；最终提示词在 `native-export/WALLPAPER.md`。Dock 图标是项目内 SVG，位于 `assets/apps/icons.svg`。

## 重新导出原生视觉

导出器副本：`native-export/WebsiteAssetExporter.swift`。此次素材基于本地 v1.7.16 组件；副本记录导出实现，网页不执行 Swift。

```sh
swift build
.build/debug/ClampEverything --export-website "$PWD/site/assets/native"
```

导出使用临时资料库与离屏透明窗口，不读取个人文件。修改原生视图后应重新导出。

## 预览与验证

```sh
cd site
python3 scripts/prepare-files.py
npm run check
npm test
npm run preview
```

打开 http://127.0.0.1:5173/ 。安装 Playwright 后运行 `node tests/browser.cjs`；`SITE_URL` 可指定公开站点，`PLAYWRIGHT_MODULE` 可指定已有安装。

浏览器回归涵盖：普通鼠标选择与双击打开、Option 夹取各类文件与聊天文字图片、提前松键取消与重新按键、真实 PDF 渲染、Word 正文预览与下载摘要校验、原文与原件保留、文稿分页、收放、窗口与 Dock 语义、实际视频播放、跨应用复制、信息草稿、取消及窄屏桌面。

GitHub Actions 发布静态页面、JS 和 assets；测试与原生导出参考代码不进入部署包。

第三方：`assets/vendor/pdfjs/` 保留 PDF.js 原始 Apache-2.0 许可证；运行时不请求 CDN。

当前下载按钮直达 [v1.7.16 arm64 DMG](https://github.com/Quartzsyr/ClampEverything/releases/download/v1.7.16/ClampEverything-1.7.16-arm64.dmg)，同一窗口提供详细 Release 说明、SHA-256 和开发签名状态。

新增窗口回归：`node tests/windows.cjs` 验证所有应用和设置面板的拖动与边角缩放、五种屏幕下下载入口的首屏可见性，并实际下载、校验 DMG。
