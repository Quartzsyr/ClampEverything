# 产品说明与练习资料

2026-10-17 为屏幕夹子的网页桌面制作，全部为专用演示内容。

- `assets/files/屏幕夹子快速上手.pdf`：三页指南，使用当前网页实际操作截图；采用 Arial Unicode 字体子集，逐页渲染复核。
- `assets/files/我的桌面收纳计划.docx`：三页可编辑计划，使用系统中文字体；通过文档技能 render_docx.py 渲染，并逐页检查。
- `assets/files/QuickNote.swift`：完整 macOS SwiftUI 便笺示例，swiftc 类型检查通过；网页仅编辑代码文件。
- `assets/files/夹取操作提示.txt`：可夹取的操作便笺。
- `assets/files/桌面整理示例.json`：可阅读的虚构资料清单，明确不属于应用导入格式。
- `assets/files/夹取操作讲解.wav`：26.45 秒中文合成语音，macOS Tingting，195 语速，22050 Hz 单声道 PCM。文字稿在本目录和演示素材 ZIP 中；不是真人录音。
- `assets/files/屏幕夹子入门资料.zip`：与实际资料文件夹一致的八个文件。
- `assets/files/屏幕夹子演示素材包.zip`：额外包含操作讲解文字稿。

路径均相对于 `site/`。现有实拍照片和实际操作视频继续使用用户提供的文件，不以新生成内容替代。

## 重建

先运行 `python3 site/scripts/prepare-onboarding.py`，再用现有构建执行：

```sh
CLAMP_WEBSITE_EXISTING_FILES=1 .build/debug/ClampEverything --export-website "$PWD/site/assets/native"
python3 site/scripts/finalize-onboarding.py
node site/scripts/prepare-native-media.cjs
python3 site/scripts/prepare-files.py
```

生成时需要 python-docx、reportlab、Pillow、PyMuPDF；图像转换需要 sharp。字体取自当前 Mac 系统，不单独发布字体文件。LibreOffice 的字体配置需要包含 `/System/Library/Fonts` 与其 `Supplemental` 目录，以避免中文渲染成方框。
