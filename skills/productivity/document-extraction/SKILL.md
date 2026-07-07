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
docling report.pdf -o report.md
docling report.pdf --format json -o report.json
docling report.pdf --format html -o report.html
docling https://arxiv.org/pdf/2206.01062 -o paper.md
docling report.pdf --pipeline vlm --vlm-model granite_docling
```

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
