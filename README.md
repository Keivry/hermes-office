# hermes-office

A `nousresearch/hermes-agent`-based Docker image bundled with:

- [OfficeCLI](https://github.com/iOfficeAI/OfficeCLI)
- [PPT Master](https://github.com/hugohe3/ppt-master)
- [ImageMagick](https://github.com/ImageMagick/ImageMagick)
- [UniPDF CLI](https://github.com/unidoc/unipdf-cli)
- [Docling](https://github.com/docling-project/docling)

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
- Current pinned source ref in `Dockerfile`: `43ee46b61cfc130af91c18be7d807bdb538f6a7e`

### ImageMagick
- Installed from the distro package as `imagemagick`
- CLI entrypoint is usually `magick`; on some Debian-family builds you may still use `convert`, `identify`, `montage`, etc.

### UniPDF CLI
- Built from source in a multi-stage Docker build
- Installed to `/usr/local/bin/unipdf`
- Current pinned version in `Dockerfile`: `v0.14.0`
- **Important:** UniPDF CLI requires a runtime license to operate

### Docling
- Installed into `/opt/tools/docling/.venv`
- Symlinked to `PATH` as `/usr/local/bin/docling`
- Current pinned version in `Dockerfile`: `2.91.0`
- Current image installs the base `docling` package (not the optional VLM extras)

## Included extra system packages

The image adds these packages beyond the official Hermes base image:

- `curl`
- `imagemagick`
- `pandoc`

`git` and `nodejs` are already present in the upstream `nousresearch/hermes-agent` image, so this repo does not reinstall them.

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

### UniPDF CLI
Typical usage:

```bash
unipdf merge merged.pdf a.pdf b.pdf
unipdf split report.pdf section.pdf 1-3,5
unipdf render -o pages.zip report.pdf
```

Runtime licensing is required. Image build verifies only that the binary exists; actual PDF operations still require runtime license env vars.
Supported environment variables include:

```bash
export UNIDOC_LICENSE_API_KEY="unidoc..."
# or
export UNIDOC_LICENSE_FILE="/path/to/license.key"
export UNIDOC_LICENSE_CUSTOMER="your-customer-name"
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

## Build and publish

The workflow publishes to GHCR as:

- `ghcr.io/<owner>/hermes-office:latest`
- `ghcr.io/<owner>/hermes-office:<hermes-agent-version>`

Triggers:

- push to `main` affecting `Dockerfile`, workflow, or `README.md`
- daily scheduled check
- manual `workflow_dispatch`

## Notes

- The scheduled workflow currently checks whether the **base Hermes image** changed, just like `hermes-matrix`.
- Manual dispatch can be used to rebuild after updating pinned upstream versions.
- `PaddleOCR` is intentionally **not** bundled here; you said it will be deployed separately on another server later.
- If needed later, upstream-change detection for OfficeCLI releases, PPT Master commits, UniPDF CLI tags, and Docling versions can be added.
