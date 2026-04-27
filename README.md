# hermes-office

A `nousresearch/hermes-agent`-based Docker image bundled with:

- [OfficeCLI](https://github.com/iOfficeAI/OfficeCLI)
- [PPT Master](https://github.com/hugohe3/ppt-master)
- [ImageMagick](https://github.com/ImageMagick/ImageMagick)
- [Docling](https://github.com/docling-project/docling)
- [pdfcpu](https://github.com/pdfcpu/pdfcpu)
- [qpdf](https://github.com/qpdf/qpdf)
- [poppler-utils](https://poppler.freedesktop.org/)
- [Bun](https://bun.sh/)
- [ClawMem](https://github.com/yoloshii/ClawMem)

This repository reuses the same GitHub Actions build/publish pattern as `Keivry/hermes-matrix`, but targets Office document automation, image processing, document/PDF conversion, and ClawMem-backed long-term agent memory.

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

### Bun
- Installed as a pinned standalone binary at `/usr/local/bin/bun`
- Current pinned version in `Dockerfile`: `1.3.13`
- Added because ClawMem requires Bun at runtime

### ClawMem
- Installed globally as `clawmem` at `/usr/local/bin/clawmem`
- Current pinned version in `Dockerfile`: `0.10.1`
- The Hermes memory provider plugin is staged under `/opt/tools/clawmem-plugin`
- On container start, the entrypoint syncs that plugin into `$HERMES_HOME/plugins/clawmem`
- The image defaults to **external-model / remote-GPU** style operation:
  - `CLAWMEM_SERVE_MODE=external`
  - `CLAWMEM_NO_LOCAL_MODELS=true`
  - `CLAWMEM_PROFILE=balanced`
- The image also auto-starts a local `clawmem serve` REST sidecar bound to `127.0.0.1:${CLAWMEM_SERVE_PORT:-7438}` unless one is already running
- ClawMem state defaults to persistent paths under `/opt/data`:
  - `INDEX_PATH=/opt/data/state/clawmem/index.sqlite`
  - `CLAWMEM_FOCUS_ROOT=/opt/data/state/clawmem/sessions`
  - transcripts under `/opt/data/clawmem-transcripts`

## Included extra system packages

The image adds these packages beyond the official Hermes base image:

- `curl`
- `imagemagick`
- `libcairo2-dev`
- `pandoc`
- `pkg-config`
- `poppler-utils`
- `qpdf`
- `unzip`
- `xz-utils`

Docling-specific Python artifacts are pinned in the Dockerfile rather than installed from floating latest releases, to stay compatible with the upstream Hermes `uv` freshness window.

## Runtime environment

Environment variables baked into the image:

- `OFFICECLI_SKIP_UPDATE=1`
- `PPT_MASTER_HOME=/opt/tools/ppt-master`
- `PPT_MASTER_VENV=/opt/tools/ppt-master/.venv`
- `DOCLING_HOME=/opt/tools/docling`
- `DOCLING_VENV=/opt/tools/docling/.venv`
- `CLAWMEM_BIN=/usr/local/bin/clawmem`
- `CLAWMEM_SERVE_PORT=7438`
- `CLAWMEM_SERVE_MODE=external`
- `CLAWMEM_PROFILE=balanced`
- `CLAWMEM_NO_LOCAL_MODELS=true`
- `INDEX_PATH=/opt/data/state/clawmem/index.sqlite`
- `CLAWMEM_FOCUS_ROOT=/opt/data/state/clawmem/sessions`
- `HERMES_CLAWMEM_PLUGIN_SOURCE=/opt/tools/clawmem-plugin`
- `HERMES_CLAWMEM_SYNC_PLUGIN=true`
- `HERMES_CLAWMEM_AUTOSTART_SERVE=true`

## ClawMem integration model

This image is designed for the deployment shape you asked for:

1. `hermes-office` bundles the ClawMem runtime, wrapper, and Hermes plugin
2. Hermes talks to the plugin from `$HERMES_HOME/plugins/clawmem`
3. `clawmem serve` runs inside the Hermes container as a lightweight local REST sidecar
4. embedding / LLM / reranker inference is expected to run on your separate llama.cpp GPU server
5. the Hermes container is told where that GPU host lives via environment variables

### Required runtime env for remote model services

At deploy time, set at least:

```env
CLAWMEM_EMBED_URL=http://<gpu-host>:8088
CLAWMEM_LLM_URL=http://<gpu-host>:8089
CLAWMEM_RERANK_URL=http://<gpu-host>:8090
CLAWMEM_NO_LOCAL_MODELS=true
```

Optional but recommended:

```env
CLAWMEM_PROFILE=balanced
CLAWMEM_SERVE_PORT=7438
INDEX_PATH=/opt/data/state/clawmem/index.sqlite
CLAWMEM_FOCUS_ROOT=/opt/data/state/clawmem/sessions
```

### Activating the provider in Hermes

The Hermes config needs an external memory provider entry like:

```yaml
memory:
  provider: clawmem
```

After the container starts, verify inside the container:

```bash
hermes memory status
curl -H "Authorization: Bearer $CLAWMEM_API_TOKEN" http://127.0.0.1:7438/health  # omit header if no token is set
clawmem doctor
```

## GPU model stack for ClawMem

This repo includes:

- `deploy/clawmem-models/compose.yaml`
- `deploy/clawmem-models/README.md`

These deploy the **QMD native** ClawMem-recommended stack on a separate GPU server using the official `ghcr.io/ggml-org/llama.cpp:server-cuda` image:

- `embeddinggemma-300M-Q8_0.gguf` on `8088`
- `qmd-query-expansion-1.7B-q4_k_m.gguf` on `8089`
- `Qwen3-Reranker-0.6B-Q8_0.gguf` on `8090`

If your existing Qwen3.5 service already owns `8089`, either move that service or change the host-side mapping in the compose file and update `CLAWMEM_LLM_URL` on the Hermes side.

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

### ClawMem
Typical usage:

```bash
clawmem --version
clawmem doctor
clawmem status
clawmem collection list
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

### ClawMem
```bash
clawmem doctor
curl -H "Authorization: Bearer $CLAWMEM_API_TOKEN" http://127.0.0.1:7438/health  # omit header if no token is set
```

## Build and publish

The workflow publishes to GHCR as:

- `ghcr.io/<owner>/hermes-office:latest`
- `ghcr.io/<owner>/hermes-office:<hermes-agent-version>`

Triggers:

- push to `main` or `master` affecting `Dockerfile`, workflow, `README.md`, `docker/**`, or `deploy/**`
- daily scheduled check
- manual `workflow_dispatch`

## Notes

- The scheduled workflow currently checks whether the **base Hermes image** changed, just like `hermes-matrix`.
- Manual dispatch can be used to rebuild after updating pinned upstream versions.
- `PaddleOCR` is intentionally **not** bundled here; you said it will be deployed separately on another server later.
- `unipdf-cli` was intentionally removed because it requires runtime licensing; the image now prefers the open-source stack of `pdfcpu + qpdf + poppler-utils`.
- ClawMem's Hermes plugin currently talks to `clawmem serve` on `127.0.0.1:${CLAWMEM_SERVE_PORT}`; that is why this image runs the REST sidecar locally even when model inference is remote.
- If needed later, upstream-change detection for OfficeCLI releases, PPT Master commits, pdfcpu releases, Docling versions, Bun, and ClawMem versions can be added.
