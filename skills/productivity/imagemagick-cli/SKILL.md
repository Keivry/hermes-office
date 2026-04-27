---
name: imagemagick-cli
title: ImageMagick 图片处理命令行
description: 用 ImageMagick 处理图片转换、缩放、裁剪、压缩、水印、拼接与批量操作。适合从自然语言任务直接落到 CLI。
version: 1.0.0
tags: [image, imagemagick, convert, resize, watermark, crop]
---

适用场景
---
当用户要：
- 转图片格式（png/jpg/webp/tiff/pdf 之间转换）
- 缩放、裁剪、压缩图片
- 旋转、翻转、去白边、加边框
- 加文字水印、叠图水印
- 拼图、生成 contact sheet
- 对一批图片做相同处理

触发提示
---
用户未必会说 “ImageMagick”。以下自然语言通常都应想到它：
- “把这张图缩小到 1200 宽”
- “压缩一下图片体积”
- “批量转成 webp”
- “给图片打水印”
- “裁掉四周留白”
- “把多张图拼成一张”

前提检查
---
优先确认命令是否存在：
```bash
command -v magick || command -v convert
```

说明：
- ImageMagick 7 通常用 `magick`
- Debian 系旧包有时仍使用 `convert`、`identify`、`montage`
- 优先尝试 `magick`；若不存在，再退回旧命令

最常用命令
---

格式转换：
```bash
magick input.png output.jpg
```

缩放：
```bash
magick input.jpg -resize 1600x1600\> output.jpg
```

裁剪中心区域：
```bash
magick input.jpg -gravity center -crop 1200x800+0+0 +repage output.jpg
```

去白边：
```bash
magick input.png -trim +repage output.png
```

压缩 JPEG：
```bash
magick input.jpg -strip -interlace Plane -quality 82 output.jpg
```

转 WebP：
```bash
magick input.png -quality 80 output.webp
```

加文字水印：
```bash
magick input.jpg -gravity southeast -fill 'rgba(255,255,255,0.45)' -pointsize 28 -annotate +24+24 'CONFIDENTIAL' output.jpg
```

拼 contact sheet：
```bash
magick montage *.png -tile 3x -geometry +16+16 contact-sheet.png
```

查看图片信息：
```bash
magick identify -verbose input.png
```
如果 `magick identify` 不可用，也可：
```bash
identify -verbose input.png
```

批量处理思路
---
批量转 webp：
```bash
for f in *.png; do magick "$f" -quality 80 "${f%.png}.webp"; done
```

批量压缩 jpg：
```bash
for f in *.jpg; do magick "$f" -strip -interlace Plane -quality 82 "$f"; done
```

成功判断
---
- 退出码为 `0`
- 输出文件存在且大小/格式符合预期
- 必要时用 `identify` 或 `magick identify` 检查结果尺寸与格式

注意事项
---
- 涉及 PDF 输入/输出时，受 ImageMagick 安全策略影响，某些发行版可能默认限制 PDF coder；如果报 policy error，不要硬改系统策略，优先改用更合适的 PDF 工具。
- 对用户给出的原图做 destructive overwrite 前，优先输出到新文件名，除非用户明确要求覆盖。
- 如果任务核心是 PDF 内容提取/结构化转换，不要硬用 ImageMagick，优先考虑 `docling-local` 或 `ocr-and-documents`。
- 如果任务核心是 PDF 合并、拆分、加水印、页重组等文件工程操作，优先考虑 `pdfcpu-local` 或 `pdf-structure-tools`。
