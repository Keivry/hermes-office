---
name: pdf-structure-tools
title: qpdf 与 poppler-utils PDF 结构工具
description: 用 qpdf 与 poppler-utils 做 PDF 的结构变换、加解密、页选择、信息查看、文本提取、图片提取与页面转图片。
version: 1.0.0
tags: [pdf, qpdf, poppler, pdftotext, pdfimages, pdfinfo]
---

适用场景
---
当用户要：
- 做内容保持型 PDF 结构变换
- 用页码重组 PDF
- 给 PDF 加密/解密
- 快速查看 PDF 元信息
- 从 PDF 中提取纯文本
- 从 PDF 中提取嵌入图片
- 把 PDF 页面转成 png/jpg

触发提示
---
以下自然语言通常应想到这些工具：
- “只保留第 1、2、5 页”
- “解密这个 pdf”
- “提取这个 pdf 的文字”
- “把 pdf 每页导出成图片”
- “看一下这个 pdf 的页数和元数据”
- “把两个 pdf 拼起来但尽量别重渲染”

前提检查
---
```bash
command -v qpdf
command -v pdfinfo
command -v pdftotext
command -v pdfimages
command -v pdftoppm
```

最常用命令
---
查看信息：
```bash
pdfinfo report.pdf
```

提取文本：
```bash
pdftotext report.pdf report.txt
```

提取图片：
```bash
pdfimages -all report.pdf img_prefix
```

页面转 PNG：
```bash
pdftoppm -png report.pdf page
```

合并 PDF：
```bash
pdfunite a.pdf b.pdf merged.pdf
```

拆成单页：
```bash
pdfseparate report.pdf page-%d.pdf
```

qpdf 页选择重组：
```bash
qpdf input.pdf --pages . 1-3,5 -- output.pdf
```

qpdf 解密：
```bash
qpdf --password=secret --decrypt protected.pdf plain.pdf
```

qpdf 加密：
```bash
qpdf --encrypt userpass ownerpass 256 -- input.pdf protected.pdf
```

推荐工作流
---
1. 如果只是看 PDF 信息/抽文字/抽图/页面转图片，优先 poppler-utils
2. 如果要做结构保持型页重组或加解密，优先 qpdf
3. 如果要更通用的 PDF 操作入口，优先 `pdfcpu-local`
4. 如果要文档理解/markdown/json 输出，优先 `docling-local`

成功判断
---
- 退出码为 `0`
- 输出文件存在
- 抽取到的文本/图片非空
- 加解密后可再次用 `pdfinfo` 或 `qpdf --check`（如需要）检查

重要边界
---
- 这组工具更偏**低层、稳定、组合式**。
- 对 agent 来说，`pdfcpu-local` 更像主操作面；`pdf-structure-tools` 更适合结构保持、信息查看、快速抽取与底层补刀。
