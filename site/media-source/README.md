# 演示摄影素材

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
