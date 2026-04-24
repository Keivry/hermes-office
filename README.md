# hermes-office

A `nousresearch/hermes-agent`-based Docker image bundled with:

- [OfficeCLI](https://github.com/iOfficeAI/OfficeCLI)
- [PPT Master](https://github.com/hugohe3/ppt-master)
- [ImageMagick](https://github.com/ImageMagick/ImageMagick)
- [Docling](https://github.com/docling-project/docling)
- [pdfcpu](https://github.com/pdfcpu/pdfcpu)
- [qpdf](https://github.com/qpdf/qpdf)
- [poppler-utils](https://poppler.freedesktop.org/)

This repository reuses the same GitHub Actions build/publish pattern as `Keivry/hermes-matrix`, but targets Office document automation, image processing, and document/PDF conversion.

## What gets installed

### OfficeCLI
- Installed as a standalone binary at `/usr/local/bin/officecli`
- Available directly on `PATH`
- Current pinned version in `Dockerfile`: `v1.0.54`

### PPT Master
- Extracted to `/opt/tools/ppt-master`
- Python virtual environment created at `/opt/tools/ppt-master/.venv`
- Dependencies installed from `requirements.txt`
- `libcairo2-dev` + `pkg-config` are included because the current `svglib` dependency chain may pull `rlpycairo` / `pycairo` during install
- Current pinned source ref in `Dockerfile`: `43ee46b61cfc130af91c18be7d807bdb538f6a7e`

### ImageMagick
- Installed from the distro package as `imagemagick`
- CLI entrypoint is usually `magick`; on some Debian-family builds you may still use `convert`, `identify`, `montage`, etc.

### Docling
- Installed into `/opt/tools/docling/.venv`
- Exposed on `PATH` via `ENV PATH="/opt/tools/docling/.venv/bin:${PATH}"`
- Current pinned version in `Dockerfile`: `2.89.0`
- Installed in two steps for stability while **preserving** the upstream Hermes `uv` freshness policy:
  1. install exact pinned CPU wheels for `torch==2.10.0+cpu` and `torchvision==0.25.0+cpu`
  2. install `docling==2.89.0` from the normal Python package index
- This keeps the `exclude-newer = "7 days"` supply-chain protection in effect, avoids mixed-index resolution edge cases, and avoids pulling newer Docling releases that are outside the current freshness window
- Current image installs the base `docling` package (not the optional VLM extras)

### pdfcpu
- Installed as a standalone binary at `/usr/local/bin/pdfcpu`
- Current pinned version in `Dockerfile`: `0.12.0`
- Best suited for open-source PDF CLI operations such as merge, split, validate, optimize, watermark, rotate, forms, and image extraction

### qpdf
- Installed from the distro package as `qpdf`
- Best suited for content-preserving structural PDF transformations, encryption/decryption, page selection, and repair-friendly workflows

### poppler-utils
- Installed from the distro package as `poppler-utils`
- Provides utilities such as `pdfinfo`, `pdftotext`, `pdfimages`, `pdftoppm`, `pdfseparate`, and `pdfunite`

## Included extra system packages

The image adds these packages beyond the official Hermes base image:

- `curl`
- `imagemagick`
- `libcairo2-dev`
- `pandoc`
- `pkg-config`
- `poppler-utils`
- `qpdf`
- `xz-utils`

Docling-specific Python artifacts are pinned in the Dockerfile rather than installed from floating latest releases, to stay compatible with the upstream Hermes `uv` freshness window.

## Runtime environment

Environment variables baked into the image:

- `OFFICECLI_SKIP_UPDATE=1`
- `PPT_MASTER_HOME=/opt/tools/ppt-master`
- `PPT_MASTER_VENV=/opt/tools/ppt-master/.venv`
- `DOCLING_HOME=/opt/tools/docling`
- `DOCLING_VENV=/opt/tools/docling/.venv`

## Tool-specific notes

### ImageMagick
Typical usage:

```bash
magick input.png -resize 1600x1600\> output.png
magick input.jpg -gravity south -pointsize 28 -annotate +0+24 "draft" watermarked.jpg
```

If `magick` is unavailable in the packaged version, try the legacy commands:

```bash
convert input.png -resize 1600x1600\> output.png
identify input.png
montage *.png -tile 2x -geometry +16+16 contact-sheet.png
```

### pdfcpu
Typical usage:

```bash
pdfcpu validate report.pdf
pdfcpu merge merged.pdf a.pdf b.pdf
pdfcpu split -m page report.pdf outdir 1 3 5
pdfcpu images extract report.pdf outdir
pdfcpu form export form.pdf fields.json
```

### qpdf
Typical usage:

```bash
qpdf input.pdf --pages . 1-3,5 -- output.pdf
qpdf --encrypt user owner 256 -- input.pdf protected.pdf
qpdf --password=secret --decrypt protected.pdf plain.pdf
```

### poppler-utils
Typical usage:

```bash
pdfinfo report.pdf
pdftotext report.pdf report.txt
pdfimages -all report.pdf img_prefix
pdftoppm -png report.pdf page
pdfunite a.pdf b.pdf merged.pdf
```

### Docling
Typical usage:

```bash
docling report.pdf -o report.md
docling https://arxiv.org/pdf/2206.01062 -o paper.md
docling report.pdf --format json -o report.json
```

## Typical usage inside the container

### OfficeCLI
```bash
officecli --version
officecli create demo.pptx
officecli view demo.pptx outline
```

### PPT Master
```bash
cd /opt/tools/ppt-master
/opt/tools/ppt-master/.venv/bin/python skills/ppt-master/scripts/project_manager.py init demo --format ppt169
```

### Docling
```bash
docling sample.pdf -o sample.md
```

### pdfcpu
```bash
pdfcpu merge merged.pdf a.pdf b.pdf
```

## Build and publish

The workflow publishes to GHCR as:

- `ghcr.io/<owner>/hermes-office:latest`
- `ghcr.io/<owner>/hermes-office:<hermes-agent-version>`

Triggers:

- push to `main` or `master` affecting `Dockerfile`, workflow, or `README.md`
- daily scheduled check
- manual `workflow_dispatch`

## Notes

- The scheduled workflow currently checks whether the **base Hermes image** changed, just like `hermes-matrix`.
- Manual dispatch can be used to rebuild after updating pinned upstream versions.
- `PaddleOCR` is intentionally **not** bundled here; you said it will be deployed separately on another server later.
- `unipdf-cli` was intentionally removed because it requires runtime licensing; the image now prefers the open-source stack of `pdfcpu + qpdf + poppler-utils`.
- If needed later, upstream-change detection for OfficeCLI releases, PPT Master commits, pdfcpu releases, and Docling versions can be added.
