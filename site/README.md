# 屏幕夹子交互桌面

GitHub Pages 静态宣传页，无第三方运行时依赖。下载链接始终指向最新公开 Release；网页的交互基准是本地桌面应用实现，不能据此推断公开版已包含全部功能。

## 操作依据

| 桌面源代码 | 网页行为 |
| --- | --- |
| `ClampCore/HoldShortcut.swift`, `PointClampController.receive` | 按住 Option，按下对象，保持修饰键拖动，松开鼠标放置。提前松开 Option、Esc、右键取消；完成后必须松开并重新按 Option |
| `PointClampController.capture`, `CursorPickupMotion.swift` | 压缩、抬起、缩入夹口、随指针移动、释放时放置；释放位置固定，不随之后鼠标移动漂移 |
| `PaperMotion.swift`, `Windows.swift` | 42 点边缘吸附；64×60 收起区域；悬停 350ms 展开，离开 450ms 收起，点击展开保持 |
| `HangingMetalClip.swift`, `MinimalSurfaceLayout.swift` | 夹子与纸面绕同一悬点翻转；夹子约 20×26 点，独立于内容大小；缩略内容 30×22.5 |
| `PreviewSizes.swift` | 各类型独立大小，65%–180% |
| `FolderEntryList.swift` | 条目主体复制，只有右侧箭头进入目录；滚动展示所有条目 |
| `ContentDragView`, `DocumentReadingPreview` | 点击文稿主体复制；拖主体复制，拖金属夹移动；左侧装订线向外翻页 |
| `MinimalMediaObject` | 卡带、胶片的主体点击复制，不虚构内嵌播放按钮 |
| `GuideExamples.swift` | 周末计划文字、LittleNote.swift、田野手记网页和山间湖泊构图 |

## 浏览器边界

网页模拟内置文件及文件剪贴板。点击 PDF / DOCX / 文件夹 / 音视频复制的是示例文件身份，而不是将正文冒充原件；在示例访达使用 Command-V / Ctrl-V 验证交接。拖出示例内容保留原夹项。普通文本同时尝试系统文本剪贴板。

浏览器不能访问辅助功能树、Finder 文件 URL 剪贴板、系统关联应用、全局快捷键或系统屏幕边缘。右键打开/快速查看展示示例预览。没有迁移本机图像主体分割，也没有画假主体轮廓。网页不宣称能替代原生应用。触屏访问仅浏览；完整夹取流程需要键盘和指针。

PDF 示例额外两页是用于测试翻页的示例内容，非软件内置 PDF 的原页；纸面和 macOS 的字体渲染在浏览器中会有差异。

## 本地验证

```sh
cd site
npm run check
npm test
npm run preview
```

打开 http://127.0.0.1:5173/ 。`tests/hold-gesture.test.mjs` 覆盖按住、提前松开、取消和重新激活。`tests/motion.test.mjs` 验证翻转和夹取物理参数。网页发布仅包含静态文件及素材，不包含原生项目或安装包。
