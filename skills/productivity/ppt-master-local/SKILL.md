---
name: ppt-master-local
title: PPT Master 本地可编辑 PPT 工作流
description: 用 ppt-master 仓库的固定脚本，从 PDF / DOCX / URL / Markdown / 文本生成原生可编辑 PPTX。
version: 1.0.0
tags: [ppt, presentation, svg, pptx, workflow, docker]
---

适用场景
---
当用户要：
- 从 PDF / DOCX / URL / Markdown / 长文本生成一整套 PPT
- 产出**原生可编辑**的 PPTX，而不是截图拼出来的伪 PPT
- 用统一工作流做设计规格、SVG 生成、后处理和导出

不要用本技能的情况
---
- 只是精细修改现有 docx/xlsx/pptx 的局部内容：优先 `officecli`
- 只是做 PDF 合并、拆分、抽取、渲染：优先 `pdfcpu-local` 或 `pdf-structure-tools`
- 只是把文档转成 markdown/json 供阅读或喂给模型：优先 `docling-local`

仓库假设
---
以下说明假设仓库已在镜像中，默认路径为：`/opt/tools/ppt-master`。
使用前先进入仓库根目录。

基础安装
---
- Python 3.10+
- 依赖安装：
  ```bash
  pip install -r requirements.txt
  ```
- 常见 Python 依赖来自 `requirements.txt`：
  - `python-pptx`
  - `PyMuPDF`
  - `mammoth`
  - `markdownify`
  - `ebooklib`
  - `nbconvert`
  - `Pillow`
  - `numpy`
  - `requests`
  - `beautifulsoup4`
  - `curl_cffi`
- 条件依赖：
  - `Node.js 18+`：仅当抓微信公众号且 `curl_cffi` 没有可用 wheel 时作为回退
  - `pandoc`：仅当要转换 `.doc/.odt/.rtf/.tex/.rst/.org/.typ`

先读这里
---
- 总入口：`skills/ppt-master/SKILL.md`
- 通用代理入口：`AGENTS.md`

关键规则
---
- 这是**严格串行**工作流，不能跨阶段打包执行。
- 真正生成页面 SVG 时，必须由主代理连续逐页完成，**不能**把 SVG 页面生成委托给子代理。
- 后处理必须顺序执行，不能把三步并成一条命令。
- 默认是 free design；只有用户明确提到模板/风格或询问模板时，才走模板分支。

最常用脚本
---
内容转 Markdown：
```bash
python3 skills/ppt-master/scripts/source_to_md/pdf_to_md.py <PDF>
python3 skills/ppt-master/scripts/source_to_md/doc_to_md.py <DOCX_or_other>
python3 skills/ppt-master/scripts/source_to_md/ppt_to_md.py <PPTX>
python3 skills/ppt-master/scripts/source_to_md/web_to_md.py <URL>
```

项目初始化：
```bash
python3 skills/ppt-master/scripts/project_manager.py init <project_name> --format ppt169
python3 skills/ppt-master/scripts/project_manager.py import-sources <project_path> <source_files_or_URLs...> --move
python3 skills/ppt-master/scripts/project_manager.py validate <project_path>
```

图片与质量检查：
```bash
python3 skills/ppt-master/scripts/analyze_images.py <project_path>/images
python3 skills/ppt-master/scripts/image_gen.py 'prompt' --aspect_ratio 16:9 --image_size 1K -o <project_path>/images
python3 skills/ppt-master/scripts/svg_quality_checker.py <project_path>
```

导出流程（必须逐条确认成功）：
```bash
python3 skills/ppt-master/scripts/total_md_split.py <project_path>
python3 skills/ppt-master/scripts/finalize_svg.py <project_path>
python3 skills/ppt-master/scripts/svg_to_pptx.py <project_path> -s final
```

标准执行顺序
---
1. 准备源材料
2. 用 source_to_md 脚本转换非 Markdown 内容
3. `project_manager.py init` 建项目
4. `import-sources --move` 把源文件归档进项目
5. 按 `skills/ppt-master/SKILL.md` 完成 strategist 阶段
6. 若需要 AI 图片，运行图片生成阶段
7. 主代理逐页生成 `svg_output/`
8. 运行 `svg_quality_checker.py`
9. 顺序执行：
   - `total_md_split.py`
   - `finalize_svg.py`
   - `svg_to_pptx.py <project_path> -s final`

输出与成功判断
---
- 导出产物位于 `exports/`
- 正常会得到两个文件：
  - 原生形状版 `.pptx`
  - `_svg.pptx` 快照版
- 成功判断：
  - 各脚本退出码为 `0`
  - `svg_quality_checker.py` 没有阻断性 error
  - 导出命令成功生成 `.pptx`

重要边界
---
- **ppt-master 适合“整套 PPT 生成工作流”。**
- 如果任务只是对现有 docx/xlsx/pptx 做精细结构编辑，优先用 `officecli`，更轻更直接。
- `ppt-master` 的核心价值是：从复杂源材料到高设计感、可编辑 PPTX 的完整流水线。

常见坑
---
- 没先读 `skills/ppt-master/SKILL.md` 就直接开工
- 跳过 strategist 阶段
- 把 Step 6 的 SVG 页面生成拆成并行/分批子任务
- 直接从 `svg_output/` 导出，而不是 `-s final`
- 把三步后处理写进同一条 shell 命令
