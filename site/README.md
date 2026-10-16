# 屏幕夹子 · 一个可交互的 Mac 桌面

公开页面：https://clamp.musefilm.top/

交互参考 [Tendedero](https://tendedero.app/) 将产品放进桌面使用场景的方式。页面打开后，文件已经摆在桌面上，信息和浏览器窗口也已经打开。浏览器直接展示屏幕夹子的介绍与下载页，首屏可点击下载 v1.7.16；这是可独立打开的真实 HTML 文件，不是截图。演示发生在使用过程中，没有「先选类型，再生成样本」的步骤。

## 桌面与应用逻辑

- 桌面直接放置 PDF、Word、视频、图片、文件夹、代码、录音、归档、文本及数据文件。普通鼠标单击选择、双击打开；按住 ⌥ Option（Windows / Linux 为 Alt）才变成夹子，按下内容并拖动，松开鼠标放置。
- 桌面图标可直接拖动摆放，位置保存在当前浏览器；拖到访达会复制文件，拖到信息会成为附件草稿。Esc 取消拖动，设置可重新整理桌面。
- 信息窗口里的文字直接读取实际 TXT 文件，收到的照片、PDF 与视频来自同一组真实文件。输入框可输入，Enter 发送、Shift+Enter 换行；备忘录正文可直接编辑。新文字在浏览器内生成为独立 TXT 文件，按原文字节计算 SHA-256，可夹取、复制、拖出或下载。夹取后原消息与原附件保留。
- Dock 只有应用：访达、信息、Safari、备忘录、QuickTime、屏幕夹子和废纸篓。它打开、激活或恢复应用窗口，不选择夹取类型。图标在独立槽位中轻微放大，运行点固定；只保留一层提示，且提示与操作反馈互相避让。
- 所有应用窗口支持拖动标题栏移动，从四边与四角调整大小，以及关闭、最小化和缩放。设置、帮助与应用信息面板同样支持移动、缩放，内容独立滚动。关闭窗口保留应用的运行状态；Dock 再次点击可打开窗口。
- 预选轮廓对照原生 `TargetGlow.swift`：文字逐行金色底纹、图片冰蓝边缘、文件紫色角标、文件夹暖金轮廓、链接薄荷色下划线。移动时减弱，停稳 280ms 后亮起；文字区域来自真实字行，滚动时按可见区域裁剪，切换目标或松键立即清除。
- 访达可以进入文件夹、返回桌面，并按名称或种类搜索。浏览器地址栏可输入，Enter 打开外部地址，刷新按钮重载真实下载页。文件右键可打开、快速查看、复制、在访达中显示、下载原文件（文件夹下载为实际 ZIP）。桌面空白区域可拖动选择文件。
- 播放器读取真实 MOV / WAV，播放控件和夹取画面分别响应。
- 拖金属夹移动已夹物件；靠边放置收起，悬停展开。拖到废纸篓可移除夹项，原文件保留；废纸篓中可放回。
- 点击已夹内容复制，拖出内容可复制到访达或信息。放入信息先成为草稿，点击发送后才进入会话。
- 没有自动播放或自动夹取。松开 Option 恢复普通鼠标；放下前松开 Option、Esc、右键或窗口失焦会取消当前夹取。一次夹取后需要松开再按 Option 才能重新开始。窗口和 Dock 保留原有操作；它们的可见文字也可单独夹成 TXT。

## 原生素材

`assets/files/` 保存专门制作的真实 PNG、TXT、三页 PDF、三页 DOCX、Swift、HTML、WAV、MOV、DAT、ZIP 及示例文件夹。`catalog.json` 记录每个原文件的 MIME、大小与 SHA-256，启动时先加载并校验，再创建浏览器 `File` 对象。桌面、聊天附件、夹项与拖出副本引用相同文件身份；拖出携带原文件字节，右键可下载原件。它们先由桌面端 `ClipStore.importFiles` 读取，再由实际 `CardSurface` / `ItemBody` / `DocumentPages` / `PhotoBody` 绘制。

`assets/native/` 保存这些原生组件的透明离屏渲染。文字字体、文件图标、目录、纸面磨损、金属夹及夹口阴影来自原生组件。`provenance.json` 记录源文件摘要，`manifest.json` 记录原文件与图像的对应关系。

- 原生组装图为 Retina 2×，四周有 32 点透明安全区。
- 悬点为左侧 `(44,26)`、右侧 `(width−44,26)`；夹子与内容一起旋转，钉子固定。
- 收起图逻辑尺寸 64×60，已包含原生 ±105° 姿态。
- PDF / DOCX 各三页均来自原文件；翻页使用单独的原生纸面，金属夹保持不动。
- 鼠标夹子三态由 `ImageGenCursorClip` 导出。

应用场景的窗口由网页实现，夹取后呈现的物件使用原生渲染。打开 PDF 使用本地打包的 [Mozilla PDF.js](https://mozilla.github.io/pdf.js/examples/) 5.6.205 直接解析文件字节并渲染所有页面；Word 的可滚动预览由 `scripts/prepare-files.py` 从 DOCX 的 OOXML 正文导出，保存原件摘要。Safari 加载真实 HTML 下载页，由页面自身响应式布局适应窗口宽度；图片直接使用 PNG 原件，音视频可播放，文本和代码读取原文件，压缩包展示真实 ZIP 条目，文件夹条目来自实际目录。

网页内部维护场景文件和剪贴板；普通文本、代码和图片同时尝试浏览器系统剪贴板。它不访问用户个人文件或真实聊天账户。初始文件与消息来自仓库中的固定素材；之后输入的文字仅存在当前浏览器会话，不会发送到真实聊天账户。

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

## GitHub 下载统计与版本记录

桌面内的下载网页从 GitHub REST Release 接口读取各版本的 DMG 附件下载次数，累计值不计入校验文件或图片附件。显示发布时间、最新版 / 预发布标记、每版次数、安装包与更新说明入口。页面打开时同步，成功数据本地缓存 10 分钟，可手动刷新；接口不可用时保留上次数据，未读取到的计数不伪装成零。

`node scripts/sync-releases.mjs` 为发布包生成真实 GitHub 快照和静态列表。部署也会在 Release 发布、编辑或删除时触发，构建凭据仅在服务器内存使用。浏览器不包含令牌。接口文档：[GitHub Releases](https://docs.github.com/en/rest/releases/releases)。

HTML 原文件通过 `.html.bin` 二进制副本读取和校验，避免自定义域名 CDN 的脚本注入改变 HTML 字节；正常预览仍打开 HTML。文件请求带原件摘要版本参数，失败后重新读取，单个文件不可用不会阻止整个桌面初始化，也不会创建空文件冒充原件。

`node tests/releases.cjs` 检查版本、下载统计、刷新及限流回退；`node tests/loading.cjs` 复现 CDN HTML 注入和单文件失败。静态测试同时核对 HTML 与二进制传输副本逐字节相同。

## 桌面细节回归

`node tests/desktop.cjs` 检查五种宽度下 Dock 放大无重叠、单一提示、图标摆放与刷新恢复、双击打开、信息和备忘录输入、独立 TXT 文件的夹取与下载，以及逐行高亮的移动/停稳状态与访达搜索。`ENGINE=webkit` 可使用已安装的 WebKit 内核运行同一测试。

可编辑文字沿用原生空白纸张与金属夹（`note-blank-*.webp`），只把真实 TXT 正文绘制在原生内容区域。空白纸张由 `CLAMP_WEBSITE_BLANK_NOTE=1 .build/debug/ClampEverything --export-website "$PWD/site/assets/native"` 离屏导出 PNG，再转换为 WebP quality 95；不触碰其他素材。

## 可编辑的真实文件与本地会话

- 信息会根据发送内容回复文字、照片、影片、PDF、Word、代码、文件夹、录音、ZIP 或网页；同类请求有多种措辞。输入状态按顺序出现，阅读旧消息或正在夹取时，新回复不会强制滚动。所有附件仍引用真实演示文件，文字回复则生成独立 TXT。联系人信息明确标识本地演示会话，不连接真实 iMessage。
- Word 点击「编辑」可修改正文、标题样式、粗体、斜体并撤销/重做；保存、⌘S 和下载均写回真实 DOCX。JSZip 3.10.1 读取原始 OOXML 包，只替换 document.xml，其余关系、主题与元数据保留。原件未编辑时不会重新打包。编辑后立即夹取会先保存最新版本，纸张展示来自当前正文的实际分页预览。
- Swift 支持编辑、语法着色、行号、光标行列、缩进、自动保存、⌘S 与下载。实际 .swift 字节、桌面缩略图、夹取预览保持一致，不在浏览器执行代码。
- DOCX、Swift 和备忘录的工作文件保存在此浏览器的 IndexedDB，刷新后恢复；浏览器不允许存储时保留当前会话的文件。初始聊天、历史消息和先前夹取的版本各自保留其文件身份。
- 桌面图标可拖到 Dock 废纸篓或废纸篓窗口，右键也可移入。⌘⌫ 移入、⌘Z 放回，支持逐项/全部放回和清空。图标原位置保留；刷新网页会恢复所有桌面示例文件并开始新的废纸篓，已编辑的文件字节及 Dock 快捷入口仍然保留。左上角夹子菜单可单独恢复桌面文件；设置里的还原桌面与文件则恢复原始演示材料并清除本地工作副本。
- 摄影图片与影片画面来自内置 image_gen；影片以生成画面编码为真实 6 秒 H.264 MOV，包含缓慢推近。最终文件、提示词与重建方式见 [media-source/README.md](media-source/README.md)。

`node tests/workspace.cjs` 验证多类回复、DOCX 格式与包内其他文件保留、代码编辑、编辑后立即夹取/下载、跨刷新恢复、废纸篓操作和真实影片播放。`ENGINE=webkit` 验证 Safari 内核。另用 macOS textutil 和 Quick Look 验证实际下载的 DOCX 可解析和渲染。

新增第三方：`assets/vendor/jszip/` 随包附带 JSZip MIT 与 Pako MIT 许可证，不依赖外部 CDN。JSZip API：[读取现有 ZIP](https://stuk.github.io/jszip/documentation/api_jszip/load_async.html)、[写回 ZIP](https://stuk.github.io/jszip/documentation/api_jszip/generate_async.html)。

旧版本的 photo/video/group PNG 地址暂时保留，供已打开的旧页面继续夹取；当前 manifest 使用更新后的摄影素材与 WebP 预览。

### 全站文字夹取与使用截图

按住 Option / Alt 可以夹取窗口标题、文件名、按钮文字、设置说明、输入框当前内容以及同源内嵌网页正文。先选择一段文字再夹，只提取选区；未选择代码片段时仍夹 Swift 原文件。文字命中和金色逐行预选使用同一识别结果，夹起的原文登记为真实 TXT 文件。PDF 优先读取自身文字层；当前图像型示例的逐行索引由 macOS Vision 从原始 PDF 本地识别，SHA-256 匹配后启用，没有改写 PDF 原件。

下载网页包含三组实际桌面操作截图，素材与取景方法记录于 `assets/usage/provenance.json`。从仓库根目录启动本地预览后，可用 `node site/scripts/capture-usage.cjs` 重新录制；通过 `PLAYWRIGHT_MODULE` 指定 Playwright 路径。PDF 索引可用 `swift site/scripts/extract-pdf-text.swift site/assets/files/旅行手记.pdf site/assets/files/旅行手记.text.json` 更新。

新增浏览器回归：`node site/tests/text-capture.cjs`；可设置 `ENGINE=webkit` 和 `PLAYWRIGHT_BROWSERS_PATH` 检查 WebKit。覆盖正文、选区、内嵌网页、PDF、Word、代码片段、输入框、设置、原文件保留和截图加载。

### Dock 与应用菜单

黄色窗口按钮和 ⌘M 将窗口以曲面神奇效果收入对应 Dock 图标，点击该图标反向展开。PDF、Word、代码、图像、音视频、访达及设置／帮助／开发者／关于面板共用同一流程；收放保留真实文档、滚动位置、输入和编辑状态。动画使用当前窗口内容绘制网格，WebGL 不可用时保留 Canvas 曲面，关闭动效或系统减少动态效果时直接切换。窗口尺寸变化和快速重复操作不会遗留透明窗口。

桌面文件可以拖到 Dock 保存快捷入口，支持重排、拖出移除、右键移除，原文件保留。快捷入口在本地恢复，编辑桌面文件后对应入口随之更新；新夹出的 TXT 等独立文件保存自己的真实字节。图标较多时自动缩小到可读尺寸，再使用横向滚动，提示不随图标区域被裁切。

左上角夹子 Logo 打开应用菜单，包含关于、开发者信息（Quartz · UESTC · SYRQuartz@gmail.com）、设置、帮助、恢复桌面文件、所有窗口收放与 Mac 版下载。右侧菜单栏只保留夹取按键提示和时钟。支持方向键、Esc、⌘,。同源网页与 Word 文档中同样支持窗口快捷键。

窗口内容的本地栅格化使用 [html2canvas 1.4.1](https://html2canvas.hertzen.com/documentation/)，MIT 许可证保留于 `assets/vendor/html2canvas/LICENSE`；不向外上传窗口内容。曲面与纹理网格实现位于 `assets/genie-motion.js`、`assets/genie-renderer.js`。回归运行 `node site/tests/dock-genie.cjs`，可设置 `ENGINE=webkit` 检查 WebKit。

### 默认桌面布局

打开或刷新网页时，信息、下载网页、备忘录和真实视频播放器默认打开，视频等待手动播放。宽屏以下载网页为主，信息与备忘录分列左侧上下，视频放在网页下方右侧，保留桌面文件和 Dock 的操作空间。紧凑窗口中的备忘录隐藏列表侧栏，只显示可编辑纸页；窄屏保留各窗口标题栏并可从 Dock 切换。

`node site/tests/desktop-scene.cjs` 检查旧废纸篓迁移、菜单与刷新找回文件、编辑及快捷入口保留、实际视频播放、六种屏幕尺寸的初始排布和设置入口。可用 `ENGINE=webkit` 运行 Safari 内核回归。
