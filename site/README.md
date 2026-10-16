# 屏幕夹子 · 原生视觉桌面

公开页面：https://quartzsyr.github.io/ClampEverything/

鼠标默认就是夹子。切换文件只选中；在右侧文件上按下并拖动，松开鼠标放置。没有自动夹取或自动播放，不需要修饰键。Esc 或右键取消。

## 素材来源

`assets/files/` 保存真实 PNG、TXT、三页 PDF、三页 DOCX、Swift、HTML、WAV、MOV、DAT、ZIP 及示例文件夹。它们经桌面端 `ClipStore.importFiles` 读取，再交给真实 `CardSurface` / `ItemBody` / `DocumentPages` / `PhotoBody` 绘制。

`assets/native/` 是这些原生组件的透明离屏渲染，不是网页用 HTML 重排的文件内容。文字字体、原生文件图标、文件夹目录、纸面磨损、夹子、夹口阴影均来自同一次原生绘制。`provenance.json` 记录对应源文件摘要；`manifest.json` 记录文件对应关系和几何尺寸。

- 展开与收起各自导出左右侧状态，逻辑尺寸与原软件一致，Retina 2×。
- 组装图四周留 32 点透明安全区，悬点为左侧 `(44,26)`、右侧 `(width−44,26)`。
- 金属夹已包含在原生组装图内，与内容一起绕悬点翻转；钉子独立固定。
- 原生收起图为 64×60，已包含原软件 ±105° 姿态，网页不重复旋转。
- PDF 与 DOCX 各三页，页面均由真实原文件生成。翻页只转动导出的原生裸纸面，夹子保持原位。
- 鼠标夹子张开、半开、合拢三态也由 `ImageGenCursorClip` 导出。

网页使用简约纸质燕尾夹壁纸与 Liquid Glass 控件，底部 Dock 根据鼠标距离放大。壁纸由内置 image_gen 生成，最终提示词保存在 `native-export/WALLPAPER.md`。网页用 CSS / Web Animations 驱动夹取、回摆和收放。它演示软件外观，不访问用户系统文件，也不将浏览器行为伪装成系统文件操作。原文件可通过右侧「查看原文件」打开。

## 重新导出

原生导出器副本在 `native-export/WebsiteAssetExporter.swift`。此次素材由本地 v1.7.16 源码与其原生组件生成；该副本记录导出实现，不作为网页代码运行。完整原生导出入口与 `CardSurface.showsNail` 参数保留在本地桌面源码中。

```sh
swift build
.build/debug/ClampEverything --export-website "$PWD/site/assets/native"
```

导出使用隔离的临时资料库和离屏透明窗口，不读取个人文件，不对当前桌面截图。修改原生视图后应重新导出，而非在网页重画内容。

## 本地预览与验证

```sh
cd site
npm run check
npm test
npm run preview
```

浏览器打开 http://127.0.0.1:5173/ 。安装 Playwright 后可运行 `node tests/browser.cjs`；`SITE_URL` 可指定公开站点，`PLAYWRIGHT_MODULE` 可指定现有安装。

回归涵盖：无自动播放、真实文件选择、默认夹子光标、直接拖动与取消、手动放置、真实 Word 页面、原生收起/悬停展开、开发者信息及窄屏布局。GitHub Actions 只发布 HTML、CSS、JS 和 assets；原生导出参考源码与测试不进入网站部署包。
