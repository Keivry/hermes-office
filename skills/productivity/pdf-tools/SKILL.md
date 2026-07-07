---
name: pdf-tools
title: PDF Tools — qpdf, pdfcpu, nano-pdf
description: Comprehensive PDF manipulation — structure operations (merge, split, encrypt, page selection with qpdf/poppler), engineering operations (merge, split, optimize, watermark with pdfcpu), and AI-powered text editing (nano-pdf). PDF processing 时 **MUST** 加载。
version: 1.0.0
tags: [pdf, qpdf, poppler, pdfcpu, nano-pdf, document]
---

# PDF Tools

Three complementary tool layers for PDF processing. Choose based on your task.

## Decision Table

| Task | First Choice | Alternative |
|------|-------------|-------------|
| View metadata, page count | `pdfinfo` (poppler) | `pdfcpu validate` |
| Extract text | `pdftotext` (poppler) | — |
| Extract embedded images | `pdfimages` (poppler) | `pdfcpu images extract` |
| Page → images | `pdftoppm` (poppler) | — |
| Page selection/reorder | `qpdf --pages` | `pdfcpu split` / `pdfcpu merge` |
| Encrypt/decrypt | `qpdf --encrypt` / `--decrypt` | — |
| Merge multiple PDFs | `pdfunite` or `pdfcpu merge` | — |
| Split into single pages | `pdfseparate` or `pdfcpu split` | — |
| Optimize/compress | `pdfcpu optimize` | — |
| Add/remove watermark | `pdfcpu watermark` | — |
| Rotate/crop | `pdfcpu rotate` / `pdfcpu crop` | — |
| Fill/export form fields | `pdfcpu form` | — |
| AI text editing via NL | `nano-pdf edit` | — |

---

## Layer 1: poppler-utils (Low-Level Structure)

Best for: info, text extraction, image extraction, page rendering. Tools: `pdfinfo`, `pdftotext`, `pdfimages`, `pdftoppm`, `pdfunite`, `pdfseparate`.

```bash
pdfinfo report.pdf                          # metadata + page count
pdftotext report.pdf report.txt             # extract text
pdfimages -all report.pdf img_prefix        # extract embedded images
pdftoppm -png report.pdf page               # page → PNG images
pdfunite a.pdf b.pdf merged.pdf             # merge PDFs
pdfseparate report.pdf page-%d.pdf          # split into single pages
```

## Layer 2: qpdf (Structure-Preserving Operations)

Best for: page selection/reordering, encrypt/decrypt, linearization. Content-preserving — no re-rendering.

```bash
qpdf input.pdf --pages . 1-3,5 -- output.pdf        # select specific pages
qpdf --password=secret --decrypt protected.pdf plain.pdf   # decrypt
qpdf --encrypt userpass ownerpass 256 -- input.pdf protected.pdf   # encrypt
```

## Layer 3: pdfcpu (Engineering Operations)

Best for: merge/split, optimize, watermark, rotate, crop, form handling. The main PDF CLI.

```bash
pdfcpu validate report.pdf                   # check structure
pdfcpu merge merged.pdf a.pdf b.pdf          # merge
pdfcpu split report.pdf outdir               # split to directory
pdfcpu optimize in.pdf out.pdf               # compress/optimize
pdfcpu rotate in.pdf 90 out.pdf              # rotate
pdfcpu crop '10 10 10 10' in.pdf out.pdf     # crop margins
pdfcpu watermark add 'draft' 'pos:br,rot:0,scale:1 rel,op:.3' in.pdf out.pdf
pdfcpu watermark remove in.pdf out.pdf       # remove watermark
pdfcpu images extract in.pdf outdir          # extract images
pdfcpu form export in.pdf fields.json        # export form fields
pdfcpu form fill in.pdf fields.json out.pdf  # fill form
```

## Layer 4: nano-pdf (AI-Powered Text Editing)

Best for: natural-language PDF text changes (typos, title edits, content fixes without touching source file).

```bash
# Install
uv pip install nano-pdf

# Edit text on a page
nano-pdf edit deck.pdf 1 "Change the title to 'Q3 Results'"
nano-pdf edit report.pdf 3 "Update the date from January to February 2026"
nano-pdf edit contract.pdf 2 "Change client name from 'Acme Corp' to 'Acme Industries'"
```

**Note:** nano-pdf uses an LLM under the hood — requires API key. Page numbering may be 0-based or 1-based depending on version.

## Recommended Workflow

1. **Info/text/images/rendering** → poppler-utils (fastest, lowest level)
2. **Structure operations (pages, encrypt)** → qpdf (content-preserving)
3. **Engineering (merge, watermark, form)** → pdfcpu (most comprehensive)
4. **Text editing** → nano-pdf (AI-powered)
5. **Document understanding / markdown extraction** → `document-extraction`
6. **All PDF processing** → prefer `pdfcpu` as the main entry point

## Common Pitfalls

- qpdf and pdfcpu overlap in merge/split — prefer pdfcpu for these
- nano-pdf edits are LLM-based; verify output after editing
- poppler tools don't handle encrypted PDFs — use qpdf --decrypt first
- For scanned documents, use `ocr-and-documents` (marker-pdf) instead
- For markdown/JSON extraction from PDFs, use `document-extraction`
