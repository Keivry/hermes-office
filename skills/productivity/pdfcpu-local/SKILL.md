---
name: pdfcpu-local
title: pdfcpu 本地 PDF 工具箱
description: 用 pdfcpu 处理 PDF 的合并、拆分、验证、优化、旋转、裁剪、水印、图片提取与表单 JSON 导入导出。适合无许可依赖的 PDF CLI 自动化。
version: 1.0.0
tags: [pdf, pdfcpu, merge, split, optimize, watermark]
---

适用场景
---
当用户要：
- 合并 PDF
- 拆分 PDF
- 验证 PDF
- 优化/压缩 PDF
- 旋转/裁剪/裁页
- 加水印/去水印
- 提取 PDF 内图片
- 导出或填充表单 JSON

触发提示
---
以下自然语言通常应想到 `pdfcpu`：
- “把这几个 pdf 合成一个”
- “把这个 pdf 拆成单页”
- “检查这个 pdf 有没有结构问题”
- “给这个 pdf 加水印”
- “从 pdf 里提取图片”
- “导出这个表单 pdf 的字段”

前提检查
---
先确认命令：
```bash
command -v pdfcpu
```

最常用命令
---
验证：
```bash
pdfcpu validate report.pdf
```

合并：
```bash
pdfcpu merge merged.pdf a.pdf b.pdf c.pdf
```

拆分到目录：
```bash
pdfcpu split report.pdf outdir
pdfcpu split report.pdf outdir 2
```

优化：
```bash
pdfcpu optimize in.pdf out.pdf
```

旋转：
```bash
pdfcpu rotate in.pdf 90 out.pdf
```

裁剪：
```bash
pdfcpu crop '10 10 10 10' in.pdf out.pdf
```

添加文字水印：
```bash
pdfcpu watermark add 'draft' 'pos:br, rot:0, scale:1 rel, op:.3' in.pdf out.pdf
```

移除水印：
```bash
pdfcpu watermark remove in.pdf out.pdf
```

提取图片：
```bash
pdfcpu images extract in.pdf outdir
```

查看图片资源：
```bash
pdfcpu images list in.pdf
```

导出表单 JSON：
```bash
pdfcpu form export in.pdf fields.json
```

填充表单 JSON：
```bash
pdfcpu form fill in.pdf fields.json out.pdf
```

推荐工作流
---
1. 如果用户目标是 PDF 文件工程操作，优先 `pdfcpu`
2. 默认输出到新文件，避免覆盖输入
3. 对异常文件先 `validate`
4. 如目标是结构化内容抽取/markdown/json 导出，优先 `docling-local` 或 `ocr-and-documents`
5. 如只想快速抽文本/图片/信息，也可考虑 `pdf-structure-tools`

成功判断
---
- 退出码为 `0`
- 输出文件/目录存在
- 对验证命令，无 error
- 必要时用 `pdfinfo` 或再次 `pdfcpu validate` 复检输出

重要边界
---
- `pdfcpu` 是当前镜像内的**主 PDF CLI**。
- 它适合通用 PDF 工程操作，但不是 OCR 工具。
- 如用户要扫描件 OCR、复杂版面理解、markdown/json 转换，优先 `docling-local` 或 `ocr-and-documents`。
