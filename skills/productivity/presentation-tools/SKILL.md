---
name: presentation-tools
title: Presentation Tools — Create, Edit, Generate
description: Complete presentation workflow — direct .pptx editing and analysis (python-pptx, markitdown) and full from-scratch generation from PDF/DOCX/URL/Markdown sources (ppt-master). Covers template manipulation, visual QA, design ideas, and automated generation pipelines.
version: 1.0.0
tags: [ppt, presentation, pptx, slides, deck, design, workflow]
---

# Presentation Tools

Two complementary approaches to working with presentations:

| Task | Tool | Approach |
|------|------|----------|
| Read/analyze existing .pptx | python -m markitdown | Text extraction |
| Edit/create from template | python-pptx (see references/editing.md) | DOM manipulation |
| Create from scratch | pptxgenjs (see references/pptxgenjs.md) | JS-based generation |
| Generate from PDF/DOCX/URL/Markdown | ppt-master pipeline (see references/ppt-master.md) | Full workflow |
| Visual QA | Convert to images, inspect | pdftoppm + vision analysis |

---

## Direct .pptx Editing

### Reading Content
```bash
python -m markitdown presentation.pptx
python scripts/thumbnail.py presentation.pptx
```

### Editing Workflow
1. Analyze template with thumbnail.py
2. Unpack to raw XML: `python3 -c "import sys,zipfile; zipfile.ZipFile(sys.argv[1]).extractall('unpacked')" presentation.pptx`
3. Manipulate slides, edit content
4. Clean: `python scripts/clean.py unpacked/` (remove orphaned slides, media, rels)
5. Re-pack from INSIDE the dir: `(cd unpacked && rm -f ../out.pptx && zip -Xr ../out.pptx .)`
6. Validate: `python scripts/office/validate.py out.pptx --original presentation.pptx`
See references/editing.md for full detail.

### Creating from Scratch (pptxgenjs)
Use when no template is available. See references/pptxgenjs.md.

### QA (Required)
```bash
python -m markitdown output.pptx
python -m markitdown output.pptx | grep -iE "xxxx|lorem|ipsum"
python scripts/office/soffice.py --headless --convert-to pdf output.pptx
pdftoppm -jpeg -r 150 output.pdf slide
```
Use subagents for visual QA. Assume there are problems; find them. See references/design-ideas.md for design guidance.

---

## Full Presentation Generation (ppt-master)

See references/ppt-master.md for full workflow.

### Standard Sequence
1. Prepare source materials (PDF/DOCX/URL/Markdown)
2. Convert non-Markdown content via source_to_md scripts
3. project_manager.py init + import-sources
4. Run strategist phase (see ppt-master SKILL.md)
5. Generate SVG pages sequentially (NOT in parallel)
6. Run quality checks
7. Export: total_md_split.py → finalize_svg.py → svg_to_pptx.py -s final

### Output
- Two files: native shapes .pptx + _svg.pptx snapshot
- Located in exports/

### Pitfalls
- SVG page generation must be sequential, NOT parallel
- Post-processing steps one by one, not as shell chain
- Always read the full ppt-master AGENTS.md before starting
