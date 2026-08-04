---
name: document-extraction
title: Document Extraction — Text, OCR, Structured Output
description: Extract text and structured content from documents — PDF, DOCX, PPTX, HTML, images. Covers web_extract (remote), docling (local structured conversion to markdown/JSON), pymupdf (lightweight text extraction), and marker-pdf (OCR for scanned documents, equations, complex layouts).
version: 1.0.0
tags: [document, pdf, ocr, extraction, markdown, json, text]
---

# Document Extraction

Extract text and structured content from documents. Choose the right tool based on document type and requirements.

## Decision Table

| Scenario | First Choice | Alternative |
|----------|-------------|-------------|
| Remote URL (any document) | web_extract(urls=[...]) | -- |
| Local text-based PDF to markdown | docling | pymupdf |
| Local scanned PDF (OCR needed) | marker-pdf | -- |
| DOCX / PPTX / HTML to markdown | docling | python-docx / markitdown |
| Lightweight text extraction | pymupdf | pdftotext |
| Tables, equations, complex layout | marker-pdf | docling (VLM pipeline) |
| Batch processing | marker CLI | docling |

---

## Remote URL (Always Try First)

```python
web_extract(urls=["https://arxiv.org/pdf/2402.03300"])
web_extract(urls=["https://example.com/report.pdf"])
```
Handles PDF-to-markdown via Firecrawl. Only use local when URL is unavailable or fails.

---

## docling — Structured Conversion

Best for: PDF/DOCX/PPTX/HTML to Markdown/HTML/JSON/DocTags. Good for AI-consumable output.

```bash
# 本环境（hermes-office 镜像）docling 在独立 venv，PATH 已含，直接调用
# ⚠️ 必须带 --artifacts-path 指向本地模型！否则走 HF 缓存/下载，
#    缓存缺失时直接报 IncompleteSnapshotError（实测踩坑）
docling convert report.pdf --output out/ --to md --artifacts-path /opt/data/store/docling-models
docling convert report.pdf --output out/ --to json --artifacts-path /opt/data/store/docling-models
docling convert /path/to/dir/ --output out/ --to md --artifacts-path /opt/data/store/docling-models   # 批量目录
# 注意 v2.x CLI 语法：docling convert <source> --output <dir> --to <fmt>（旧版 -o 已废弃）
```

### ⚠️ 本环境 docling 模型已本地化（勿依赖 HF 下载）

- **模型位置**（持久挂载，升级镜像不丢）：`/opt/data/store/docling-models/`
  - `docling-project--docling-layout-heron/` — 布局模型（163MB，RT-DETR，CPU 可跑）
  - `docling-project--docling-models/model_artifacts/tableformer/{accurate,fast}/` — 表格模型（202.9MB + 138.7MB）
  - `RapidOcr/` — OCR 模型（PP-OCRv6 det/rec + cls + dict，约 31MB；文字版 PDF 建议 do_ocr=False 跳过）
- **为什么放 /opt/data**：/opt/tools 是镜像内层，升级镜像即被覆盖；/opt/data 是 bind mount 持久化
- **下载源**：魔搭 ModelScope（国内直连快，212MB 十几秒）— `AI-ModelScope/docling-models`
  - 下载 URL 模式：`https://modelscope.cn/models/AI-ModelScope/docling-models/resolve/master/<path>`
- **Python API 必须显式指定 artifacts_path**（否则 docling 会尝试从 HF 下载/校验快照，可能卡死或报 IncompleteSnapshotError）：
```python
from pathlib import Path
from docling.document_converter import DocumentConverter, PdfFormatOption
from docling.datamodel.base_models import InputFormat
from docling.datamodel.pipeline_options import PdfPipelineOptions, TableFormerMode

opts = PdfPipelineOptions()
opts.artifacts_path = Path("/opt/data/store/docling-models")
opts.table_structure_options.mode = TableFormerMode.FAST  # 或 ACCURATE
opts.do_ocr = False  # 文字版 PDF 不需要 OCR，避免额外下载
conv = DocumentConverter(
    allowed_formats=[InputFormat.PDF],
    format_options={InputFormat.PDF: PdfFormatOption(pipeline_options=opts)},
)
result = conv.convert("input.pdf")
print(result.document.export_to_markdown())
```

- **目录结构约定**（docling 源码硬编码）：`<artifacts_path>/<repo_folder_name>/<model_path>`
  - layout: `docling-project--docling-layout-heron/model.safetensors` + `config.json` + `preprocessor_config.json`
  - table: `docling-project--docling-models/model_artifacts/tableformer/{accurate|fast}/`（safetensors + tm_config.json）
  - ocr: `RapidOcr/`（PP-OCRv6 系列，docling-tools 预取产物）
- **RapidOcr 缺失时** CLI 报 `Prefetch them with: docling-tools models download rapidocr ...` → 执行：
  `docling-tools models download rapidocr --rapidocr-backend-lang torch:chinese -o /opt/data/store/docling-models`
- **CPU 性能实测**（4 核 CPU，无 GPU）：约 6-8 秒/页，3 页含模型加载 24 秒；100 页约 10-13 分钟。批量用 `--jobs N` 并行
- **首次转换会从 HF 下载模型**（如果 artifacts_path 未指向本地）：HF 需要代理且慢，务必用本地 artifacts

---

## pymupdf — Lightweight Extraction

Best for: fast text extraction from text-based PDFs. No models, instant.

```bash
python scripts/extract_pymupdf.py document.pdf
python scripts/extract_pymupdf.py document.pdf --markdown
python scripts/extract_pymupdf.py document.pdf --tables
python scripts/extract_pymupdf.py document.pdf --images out/
python scripts/extract_pymupdf.py document.pdf --pages 0-4
```

---

## marker-pdf — OCR and Complex Layouts

Best for: scanned PDFs, OCR (90+ languages), equations, tables, forms, reading order.

```bash
python scripts/extract_marker.py document.pdf
python scripts/extract_marker.py document.pdf --json
python scripts/extract_marker.py scanned.pdf
python scripts/extract_marker.py document.pdf --use_llm
```

**CLI:**
```bash
marker_single document.pdf --output_dir ./output
marker /path/to/folder --workers 4
```

**Install:**
```bash
pip install marker-pdf  # Requires ~5GB for PyTorch + models
pip install pymupdf pymupdf4llm
```

---

## Workflow Recommendations

1. **Remote URL** to web_extract first
2. **Local text PDF to markdown** to docling
3. **Scanned PDF / OCR** to marker-pdf
4. **Fast text extraction** to pymupdf
5. **DOCX** to python-docx
6. **PPTX** to python -m markitdown presentation.pptx
