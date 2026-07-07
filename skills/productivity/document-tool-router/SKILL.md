---
name: document-tool-router
title: 文档/图片/Office 工具路由卡
description: 在 Office、PPT、PDF、图片、OCR、文档理解任务之间做自然语言路由，优先选对工具，再执行。文档处理/Office/PDF/图片/OCR 路由决策 时 **MUST** 加载。
version: 1.0.0
tags: [router, office, pdf, image, ppt, ocr]
---

用途
---
这个技能不是具体执行工具，而是**路由卡**：
当用户用自然语言提出 Office / PDF / 图片 / OCR / 文档理解任务时，先决定应走哪条能力，再加载对应技能或工具。

先做哪一步
---
1. 先识别用户要的是：
   - **编辑现有 Office 文件**
   - **生成整套 PPT**
   - **PDF 文件工程操作**
   - **PDF/文档内容抽取或结构化转换**
   - **图片处理**
   - **扫描件/OCR**
2. 再选择最合适的技能或工具。
3. 不要因为某个工具"已经装在镜像里"就强行使用；以任务匹配度优先。

路由决策表
---

### A. 用户要精细修改现有 Office 文件
典型说法：
- "改一下这个 docx 的标题样式"
- "把 Excel 的 A1 改成季度汇总"
- "删掉这个 pptx 第一页第二个形状"
- "检查这个 pptx 有哪些格式问题"

优先：`officecli`

原因：
- 对 `.docx/.xlsx/.pptx` 做 DOM 式精确编辑最合适
- 适合已有文件的局部修改、检查、增删改

---

### B. 用户要生成一整套高设计感 PPT
典型说法：
- "把这个 PDF 做成 PPT"
- "根据这篇文章生成汇报幻灯片"
- "给我做一套完整 deck"

优先：`presentation-tools` (ppt-master 分支)

原因：
- 这是完整 PPT 生成工作流，不是简单编辑器
- 适合从 PDF/DOCX/URL/长文到原生可编辑 PPTX

如果用户只是要**读取/分析/编辑现有 PPTX**，改走：`presentation-tools` (Direct .pptx Editing 分支)

---

### C. 用户提到任何 `.pptx`，尤其是读取/分析/修改已有演示文稿
典型说法：
- "帮我看看这个 pptx 里写了什么"
- "提取这个演示文稿的内容"
- "基于这个现有 deck 改版"

优先：`presentation-tools` (现有 deck 处理分支)

原因：
- 统一在 `presentation-tools` umbrella 下
  - 现有 deck 处理 = `presentation-tools` 的 Direct .pptx Editing 分支
  - 从材料生成整套新 deck = `presentation-tools` 的 ppt-master 分支

---

### D. 用户要 PDF 文件工程操作
典型说法：
- "合并这几个 pdf"
- "拆分这个 pdf"
- "给 pdf 加水印"
- "优化一下 pdf 体积"
- "导出这个表单字段"

优先：`pdf-tools`

经验规则：
- `pdfcpu` 层：主工程入口（合并、拆分、水印、优化、表单）
- `qpdf/poppler` 层：结构保持、加解密、页选择、快速抽文本/抽图
- `nano-pdf` 层：AI 自然语言文本编辑

---

### E. 用户要快速查看 PDF 信息、抽文字、抽图片、按页转图片
典型说法：
- "看这个 pdf 有多少页"
- "提取 pdf 的文字"
- "把 pdf 每页导出成 png"
- "把嵌入图片提出来"

优先：`pdf-tools` (poppler 分支)

---

### F. 用户要文档理解、结构化转换、转 Markdown / JSON
典型说法：
- "把这个 pdf 转 markdown"
- "提取这个文档的正文和表格"
- "给我一个适合喂给模型的文档版本"
- "把这篇论文转成 md/json"

优先顺序：
1. 如果是远程 URL，且只需快速内容获取：先考虑 `document-extraction` 中的 `web_extract` 路线
2. 如果是本地文档或需要更可控的本地转换：`document-extraction` 的 docling 分支
3. 如果是扫描件/OCR 重场景：`document-extraction` 的 marker-pdf 分支

---

### G. 用户要扫描件 OCR / OCR PDF / 图文识别
典型说法：
- "这个扫描件识别一下"
- "给这个 pdf 加 OCR 文本层"
- "从图片里识别正文"
- "提取扫描版 PDF 的文字"

优先：`document-extraction` (marker-pdf 分支)
- 将来远端 PaddleOCR 服务准备好后，再加新的 OCR skill/workflow 对接

---

### H. 用户要图片处理
典型说法：
- "把这张图缩小到 1200 宽"
- "压缩一下图片体积"
- "批量转 webp"
- "给图片打水印"
- "裁掉四周留白"
- "把多张图拼成一张"

优先：`imagemagick-cli`

原因：
- 这是图片 CLI 主入口
- 不要为了简单图片任务误走 `document-extraction` 或 PDF 工具

冲突处理规则
---
- **已有 Office 文件的精细修改**：`officecli` 胜过 `presentation-tools`
- **整套新 PPT 生成**：`presentation-tools` (ppt-master 分支) 胜过 `document-extraction`
- **PDF 文件工程操作**：`pdf-tools` 胜过 `document-extraction`
- **文档理解/markdown/json 输出**：`document-extraction` 胜过 `pdf-tools`
- **图片处理**：`imagemagick-cli` 胜过其他所有文档工具

最简口诀
---
- 改 Office：`officecli`
- 看/改现有 PPTX / 从材料生成整套 PPT：`presentation-tools`
- 合并拆分加水印 PDF：`pdf-tools`
- 文档转 markdown/json / OCR：`document-extraction`
- 修图压图裁图：`imagemagick-cli`

注意事项
---
- 不要因为用户没说技能名就要求他补技能名；应根据自然语言主动路由。
- 若任务同时跨多个域，按主目标选主技能，再用其他工具补刀。
- 如果判断不清楚，就优先问自己：
  - 这是**文件工程操作**，还是**内容理解/结构化导出**？
  - 这是**编辑已有文件**，还是**生成新文件**？
