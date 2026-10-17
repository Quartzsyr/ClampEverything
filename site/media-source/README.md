# 网站照片与宣传视频

## 当前使用的实际文件（2026-10-17）

用户明确提供两张实拍风景照片和一段应用实际操作录屏，用于替换网站演示素材。湖泊照片保存为 `../assets/files/山间湖泊.png`；牧场照片保存为 `../assets/files/云下牧场.jpg`。网页版本均为 1440×960，保留画面比例，转换时不携带原始 EXIF。原始 6000×4000 图片和下载目录中的录屏不纳入仓库。

宣传视频为 `../assets/files/屏幕夹子-实际操作演示.mov`，109 秒，1280×848、30 fps、H.264 + AAC。原始录屏的 1280×720 画面完整保留，下方增加 128 像素品牌与字幕区域，不遮挡操作。保留原声，未添加配音或音乐。字幕分为夹取、展开、文稿翻页、材料收纳、跨窗口使用和官网下载等段落，末尾显示 `clamp.musefilm.top`。

字幕源文件保存在 `promotional/`：`captions.json`、`captions.ass`，以及可独立使用的 SRT/VTT。制作脚本为 `../scripts/prepare-promotional.py`，通过 `--video`、`--photo`、`--secondary-photo` 接收用户原件路径；需要 Pillow、imageio-ffmpeg。

桌面默认播放器、聊天视频附件和下载网页中的宣传播放器共用这个实际视频。聊天请求照片时轮流发送两张实拍照片；屏幕夹子入门资料文件夹和 ZIP 包含两张照片。夹取后的照片、视频、文件夹和材料组预览由现有原生 `CardSurface` 重新离屏导出，新增照片仍使用真实的夹子、纸面和收起样式。

重建新媒体的原生预览（保留剪辑后的视频）：

```sh
swift build
CLAMP_WEBSITE_EXISTING_FILES=1 .build/debug/ClampEverything --export-website "$PWD/site/assets/native"
python3 site/scripts/finalize-onboarding.py
node site/scripts/prepare-native-media.cjs
python3 site/scripts/prepare-files.py
```

入门文件夹和素材包由 `prepare-onboarding.py` 打包，再运行 `prepare-files.py` 更新大小和摘要。新增实际媒体使网站静态资源预算由 20 MB 调整至 50 MB，视频播放器使用按需加载。

以下保留前一版生成素材的历史记录，当前网页已使用上述用户实拍照片与实际操作视频。

2026-10-16 使用内置 `image_gen`（非 CLI/API）生成两张独立摄影画面。项目采用的最终图片：`../assets/files/山间湖泊.png`（800×500 PNG）。影片画面：`lake-film.jpg`（1280×720 JPEG）。`../assets/files/湖边的风.mov` 是从第二张画面通过 AVAssetWriter 制作的实际 H.264 影片，960×540、24 fps、6 秒；带缓慢推近和横向取景变化。它不是生成模型输出的连续动态摄影。

照片和影片由实际桌面端 `CardSurface` / `PhotoBody` / `MinimalMediaObject` 重新导出夹取样式；缩略图转为 WebP quality 95，文件夹与 ZIP 中也保存同一份实际照片。

## 照片提示词

Use case: photorealistic-natural. Asset type: a real photographic demo PNG file for the ClampEverything Mac desktop website, replacing the current mountain-lake sample named 山间湖泊.png. Create one beautiful, believable landscape photograph in wide 8:5 aspect ratio. Scene: a pristine jade alpine lake with layered dark evergreen forest at the shore, distant mountain peaks in pale morning mist, small sunlit stone in foreground, delicate water ripples and reflections. Natural restrained sage, deep pine and soft warm cream colors harmonize with a minimal cream paper desktop and a silver binder clip. Premium editorial travel photography, physically realistic textures, gentle contrast, crisp recognizable foreground and calm depth, 50mm perspective. Full bleed photographic image, no border, no text, no logo, no UI, no collage, no diagram. Output a single image.

## 影片画面提示词

Use case: photorealistic-natural. Asset type: a cinematic still that will become a real 6-second H.264 travel demo movie file for the ClampEverything Mac desktop website. One wide 16:9 cinematic photograph of a quiet lakeshore at golden hour: smooth water with very subtle ripples, reeds to one side, warm light on a small wooden pier, layered green mountains across the lake, tranquil atmospheric haze. No people. Match a premium travel photographer's natural color science, realistic optics, soft sunlight, gentle olive-sage and warm ivory palette, fine organic texture, sufficient detail for a slow camera push-in and sideways pan. Compose the horizon level near the upper third, ample foreground water, clean uncluttered view. This is a film source frame, not a filmstrip or UI. No text, no typography, no watermarks, no border, no illustrations. Output a single photographic image.

## 重建原生预览

```sh
swift build
CLAMP_WEBSITE_MEDIA_ONLY=1 .build/debug/ClampEverything --export-website "$PWD/site/assets/native"
CLAMP_WEBSITE_EDITOR_STOCK=1 .build/debug/ClampEverything --export-website "$PWD/site/assets/native"
node site/scripts/prepare-native-media.cjs
python3 site/scripts/prepare-files.py
```

转换脚本使用 sharp，可通过 `SHARP_MODULE` 指向已有安装。照片更换后，同时更新 `周末旅行/山间湖泊.png`、两个 ZIP、catalog 与 provenance 摘要。原生导出使用临时资料库，不读取个人文件。
