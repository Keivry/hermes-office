---
name: docling-local
title: Docling 本地文档转换与理解
description: 用 docling CLI 将 PDF、DOCX、PPTX、HTML、图片等转换为 Markdown / HTML / JSON / DocTags，适合文档理解与结构化导出。
version: 1.0.0
tags: [docling, pdf, markdown, json, ocr, document]
---

适用场景
---
当用户要：
- 把 PDF 转成 Markdown
- 从文档中提取结构化内容
- 将 PDF / DOCX / PPTX / HTML 转成 JSON
- 处理扫描件、复杂排版、表格、阅读顺序
- 将本地文件或 URL 转换为可供后续 AI 使用的文本结构

触发提示
---
以下自然语言通常应想到 `docling`：
- “把这个 pdf 转 markdown”
- “把这个文档转成结构化 json”
- “提取这个 pdf 的正文和表格”
- “给我一个适合喂给模型的文档版本”
- “把这篇 arxiv 论文转 md”
- “把图片/文档内容解析出来”

前提检查
---
先确认命令是否存在：
```bash
command -v docling
```

常用命令
---
本地 PDF 转 Markdown：
```bash
docling report.pdf -o report.md
```

URL 转 Markdown：
```bash
docling https://arxiv.org/pdf/2206.01062 -o paper.md
```

输出 JSON：
```bash
docling report.pdf --format json -o report.json
```

输出 HTML：
```bash
docling report.pdf --format html -o report.html
```

输出 DocTags：
```bash
docling report.pdf --format doctags -o report.doctags
```

启用 VLM pipeline（仅当当前 docling 安装包含 VLM 支持时再用）：
```bash
docling report.pdf --pipeline vlm --vlm-model granite_docling -o report.md
```

调试模式：
```bash
docling report.pdf --verbose
```

推荐工作流
---
1. 如果用户只是要“看内容”或“转 markdown/json”，优先 `docling`
2. 默认先用 `--format markdown`
3. 如果后续系统要消费结构化数据，改用 `--format json`
4. 对复杂文档、扫描件、表格较多场景，必要时考虑 VLM pipeline；如果当前镜像未安装 VLM extra，则保持默认 pipeline
5. 完成后检查输出文件是否存在、内容是否非空
6. 如果用户给的是远程 URL，且目标只是快速抽取内容，也可以先考虑 Hermes 自带 `web_extract`；当需要更可控的本地转换时再用 `docling-local`

成功判断
---
- 退出码为 `0`
- 输出文件存在且非空
- 需要时可抽查前几十行确认格式正确

重要边界
---
- `docling` 适合**文档理解与结构化导出**。
- 如果用户要对 PDF 做合并、拆分、加密、渲染等文件工程操作，优先 `pdfcpu-local` 或 `pdf-structure-tools`。
- 如果用户只是要修图、裁图、压图、拼图，不要用 `docling`，优先 `imagemagick-cli`。
- 未来若远端 PaddleOCR 已部署，可将扫描/OCR 重场景再接入独立 OCR 工作流；当前镜像内不默认依赖 PaddleOCR。
