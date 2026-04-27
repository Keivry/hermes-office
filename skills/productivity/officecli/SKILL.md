---
name: officecli
title: OfficeCLI 文档创建与修改
description: 用 OfficeCLI 直接创建、读取、检查、修改 .docx / .xlsx / .pptx。适合做 Office 文档的精确编辑与自动化。
version: 1.0.0
tags: [office, docx, xlsx, pptx, cli, docker]
---

适用场景
---
当用户要：
- 创建或修改 Word / Excel / PowerPoint 文件
- 提取文档结构、文本、统计信息或问题列表
- 对元素做精确编辑（文本、位置、颜色、表格、单元格、形状等）
- 在 Docker / 无桌面环境里自动化 Office 文件处理

前提
---
- `officecli` 已在镜像内并可直接从 `PATH` 调用
- 验证命令：`officecli --version`
- 在 CI / Docker 中，优先禁用自动更新噪音：
  ```bash
  export OFFICECLI_SKIP_UPDATE=1
  ```
- 如果要长期固定镜像版本，可在镜像构建阶段执行一次：
  ```bash
  officecli config autoUpdate false
  ```

触发提示
---
用户未必会说 “OfficeCLI”。以下自然语言通常都应想到它：
- “改一下这个 docx 的标题和正文样式”
- “把 Excel 的 A1 改成季度汇总”
- “删除这个 pptx 第一页第二个形状”
- “检查这个 pptx 有哪些格式问题”
- “往这个 Word 文档里加一段执行摘要”

核心原则
---
- 优先走 **L1 读取** → **L2 DOM 编辑** → **L3 raw XML 兜底**，不要一上来就改 raw XML。
- 不确定属性名或格式时，先查内置帮助，不要猜：
  ```bash
  officecli pptx set
  officecli pptx set shape
  officecli pptx set shape.fill
  ```
- 批量修改优先用 `batch`，长会话优先用 `open` / `close`。
- 交付前至少跑一次 `validate`；PPT/文档质量检查可配合 `view issues`。

最常用命令
---

创建空文件：
```bash
officecli create demo.docx
officecli create demo.xlsx
officecli create demo.pptx
```

读取与检查：
```bash
officecli view demo.pptx outline
officecli view demo.docx text --max-lines 80
officecli view demo.xlsx stats
officecli view demo.pptx issues
officecli get demo.pptx '/slide[1]' --depth 1 --json
officecli query demo.docx 'paragraph[style=Heading1]'
```

直接修改：
```bash
officecli set demo.xlsx /Sheet1/A1 --prop value='季度汇总' --prop bold=true
officecli add demo.docx /body --type paragraph --prop text='执行摘要' --prop style=Heading1
officecli add demo.pptx / --type slide --prop title='Q4 Report'
officecli remove demo.pptx '/slide[1]/shape[2]'
officecli move demo.docx /body/p[5] --to /body --index 2
```

批量修改：
```bash
officecli batch demo.pptx --input updates.json --json
```

驻留模式（大量连续改动时更稳更快）：
```bash
officecli open demo.docx
officecli set demo.docx /body/p[1]/r[1] --prop bold=true
officecli close demo.docx
```

实时预览（尤其适合 PPT）：
```bash
officecli watch demo.pptx --port 18080
```
- 浏览器打开输出的 `http://localhost:18080`
- 可配合：
  ```bash
  officecli get demo.pptx selected --json
  ```

验证与交付检查
---
```bash
officecli validate demo.docx
officecli validate demo.xlsx
officecli validate demo.pptx
officecli view demo.pptx issues --json
```
成功判断：
- 退出码为 `0`
- `validate` 通过
- 如使用 `--json`，返回 `success=true` 或等价成功字段
- 输出文件可被下游工具正常打开

推荐工作流
---
1. 先 `view` / `get` / `query` 了解结构
2. 小改动用 `set` / `add` / `remove` / `move`
3. 多步修改用 `batch` 或 `open` / `close`
4. 交付前跑 `validate`
5. 如果是 PPT 布局微调，必要时开 `watch`

边界
---
- **OfficeCLI 最适合精确修改与自动化处理。**
- 如果用户要的是“从 PDF / 网页 / 长文直接生成一套高设计感、可编辑的完整 PPT”，优先考虑 `ppt-master-local`。
- 只有当 L1/L2 不够时，才使用 `raw` / `raw-set`。
