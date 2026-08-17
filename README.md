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
- [RTK](https://github.com/rtk-ai/rtk) (Rust Token Killer) — CLI proxy that reduces LLM token consumption by 60–90% on terminal commands, with Hermes plugin auto-enabled
- Common CLI utilities: `gh` (GitHub CLI), `jq`/`yq`, `less`, `wget`, `sqlite3`, `git-lfs`, network diagnostics (`dig`/`nslookup`/`host`, `ss`/`ip`, `netstat`, `nc`, `traceroute`, `mtr`), `rsync`, `lsof`, `strace`, `zip`/`zstd`, `tree`, `file`
- image-bundled Hermes companion skills for the office/document toolchain

This repository reuses the same GitHub Actions build/publish pattern as `Keivry/hermes-matrix`, but targets Office document automation, image processing, document/PDF conversion, ClawMem-backed long-term agent memory, and RTK-optimized LLM token usage on terminal commands.

## What gets installed

### OfficeCLI
- Installed as a standalone binary at `/usr/local/bin/officecli`
- Available directly on `PATH`
- Current pinned version in `Dockerfile`: `v1.0.144`

### PPT Master
- Extracted to `/opt/tools/ppt-master`
- Python virtual environment created at `/opt/tools/ppt-master/.venv`
- Dependencies installed from `requirements.txt`
- `libcairo2-dev` + `pkg-config` are included because the current `svglib` dependency chain may pull `rlpycairo` / `pycairo` during install
- Current pinned version in `Dockerfile`: `v4.8.0`

### ImageMagick
- Installed from the distro package as `imagemagick`
- CLI entrypoint is usually `magick`; on some Debian-family builds you may still use `convert`, `identify`, `montage`, etc.

### Docling
- Installed into `/opt/tools/docling/.venv`
- Exposed on `PATH` via `ENV PATH="/opt/tools/docling/.venv/bin:${PATH}"`
- Current pinned version in `Dockerfile`: `2.120.1`
- Installed in two steps for stability:
  1. install exact pinned CPU wheels for `torch==2.13.0+cpu` and `torchvision==0.28.0+cpu`
  2. install `docling==2.120.1` from the normal Python package index
- The upstream Hermes base image keeps `[tool.uv] exclude-newer = "14 days"` in `/opt/hermes/pyproject.toml`; the Dockerfile runs uv installs from `/tmp` to bypass that freshness window for docling and other PyPI installs
- Current image installs the base `docling` package (not the optional VLM extras)

### pdfcpu
- Installed as a standalone binary at `/usr/local/bin/pdfcpu`
- Current pinned version in `Dockerfile`: `0.15.0`
- Best suited for open-source PDF CLI operations such as merge, split, validate, optimize, watermark, rotate, forms, and image extraction

### qpdf
- Installed from the distro package as `qpdf`
- Best suited for content-preserving structural PDF transformations, encryption/decryption, page selection, and repair-friendly workflows

### poppler-utils
- Installed from the distro package as `poppler-utils`
- Provides utilities such as `pdfinfo`, `pdftotext`, `pdfimages`, `pdftoppm`, `pdfseparate`, and `pdfunite`

### Bun
- Installed as a pinned standalone binary at `/usr/local/bin/bun`
- Current pinned version in `Dockerfile`: `1.3.14`
- Added because ClawMem requires Bun at runtime

### ClawMem
- Installed globally as `clawmem` at `/usr/local/bin/clawmem`
- Current pinned version in `Dockerfile`: `0.36.0`
- The Hermes memory provider plugin is staged under `/opt/tools/clawmem-plugin`
- On container start, the s6 cont-init.d hook syncs that plugin into `$HERMES_HOME/plugins/clawmem`
- The image defaults to **external-model / remote-GPU** style operation:
  - `CLAWMEM_SERVE_MODE=external`
  - `CLAWMEM_NO_LOCAL_MODELS=true`
  - `CLAWMEM_PROFILE=balanced`
- The image also auto-starts a local `clawmem serve` REST sidecar bound to `127.0.0.1:${CLAWMEM_SERVE_PORT:-7438}` unless one is already running
- ClawMem state defaults to persistent paths under `/opt/data`:
  - `INDEX_PATH=/opt/data/state/clawmem/index.sqlite`
  - `CLAWMEM_FOCUS_ROOT=/opt/data/state/clawmem/sessions`
  - transcripts under `/opt/data/clawmem-transcripts`

### Bundled Hermes skills for this image
The image now vendors companion skills under `skills/productivity/` and copies them into `/opt/hermes/skills/` at build time so fresh deployments inherit the routing knowledge along with the tools.

Bundled image-specific skills:
- `document-tool-router`
- `officecli`
- `document-extraction`
- `imagemagick-cli`
- `pdf-tools`
- `presentation-tools`

This keeps natural-language routing aligned with the actual toolchain in the image, instead of depending on ad-hoc local skills in `/opt/data/skills`.

> **分工约定**：官方 Hermes 镜像自带的 `docx` / `xlsx` / `pdf` skills 负责**从零创建**文档（docx-js / openpyxl / reportlab、PDF AcroForm 表单、Word redlining）；本镜像的 `officecli` / `pdf-tools` 负责**编辑已有文件**（DOM 式精确编辑、PDF 工程操作 qpdf/pdfcpu/nano-pdf）。`document-tool-router` 路由卡按此分工路由。

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

Docling-specific Python artifacts are pinned in the Dockerfile rather than installed from floating latest releases, for reproducible builds.

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
CLAWMEM_EMBED_URL=http://<gpu-host>:9088
CLAWMEM_LLM_URL=http://<gpu-host>:9089
CLAWMEM_RERANK_URL=http://<gpu-host>:9090
CLAWMEM_NO_LOCAL_MODELS=true
CLAWMEM_SERVE_MODE=external
```

Verified working port mapping from production: embedding `9088`, LLM `9089`, reranker `9090`.

If the GPU server is remote, do **not** point these variables at `127.0.0.1` or `localhost` from inside the Hermes container; use the GPU host's reachable private IP or DNS name.

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
curl http://127.0.0.1:7438/health
# If CLAWMEM_API_TOKEN is set:
# curl -H "Authorization: Bearer <clawmem-api-token>" http://127.0.0.1:7438/health
clawmem doctor
```

## GPU model stack for ClawMem

This repo includes:

- `deploy/clawmem-models/compose.yaml`
- `deploy/clawmem-models/README.md`

These deploy the **QMD native** ClawMem-recommended stack on a separate GPU server using the official `ghcr.io/ggml-org/llama.cpp:server-cuda` image:

- `embeddinggemma-300M-Q8_0.gguf` on `9088`
- `qmd-query-expansion-1.7B-q4_k_m.gguf` on `9089`
- `qwen3-reranker-0.6b-q8_0.gguf` on `9090`

Important llama.cpp tuning note from the production rollout: for the embedding service, setting only `--batch-size 2048` was **not** enough. `clawmem embed` still failed with `increase the physical batch size (current batch size: 512)` until the embedding server also set `--ubatch-size 2048`. The example compose in `deploy/clawmem-models/compose.yaml` now includes both flags for `clawmem-embed`.

For the LLM and reranker services, keep the example on the more conservative `--batch-size 512` unless you have measured headroom and a reason to raise it.

If another service already owns `9089` (for example Qwen3.5), either move that service or change the host-side mapping in the compose file and update `CLAWMEM_LLM_URL` on the Hermes side.

## RTK (Rust Token Killer)

[RTK](https://github.com/rtk-ai/rtk) is a CLI proxy built as a single Rust binary (zero runtime dependencies). It intercepts terminal commands and applies four compression strategies — smart filtering, grouping, truncation, and deduplication — to reduce LLM token consumption by 60–90% on common dev commands like `git status`, `git diff`, `ls`, `grep`, `find`, `cat/read`, test runners, and build commands.

### What's in this image

- **RTK binary** at `/usr/local/bin/rtk` — pinned to `v0.45.0` (musl static binary)
- **rtk-hermes plugin** (`ogallotti/rtk-hermes` v1.2.3) — installed into Hermes' Python venv and auto-enabled in `config.yaml` via the s6 cont-init.d hook

The Hermes plugin automatically rewrites terminal commands through `rtk` *before* execution, so the agent gets token-compressed output without any manual `rtk` prefix needed.

### How it works

```
Agent calls terminal(command="cargo test --nocapture")
  → rtk-hermes pre_tool_call hook intercepts
  → plugin runs: rtk rewrite "cargo test --nocapture"
  → RTK returns: rtk cargo test --nocapture  (-90% tokens)
  → Hermes executes the rewritten command
  → RTK-filtered output reaches the model
```

### Runtime configuration (environment variables)

| Variable | Default | Description |
|---|---|---|
| `RTK_HERMES_MODE` | `rewrite` | `rewrite` (auto-apply), `suggest` (log-only), or `off` (disable) |
| `RTK_HERMES_TIMEOUT_MS` | `2000` | Max ms waiting for `rtk rewrite` per command |
| `RTK_HERMES_PREVIEW_MARKER` | `true` | Prefix rewritten commands with `: RTK &&` in Hermes tool preview |
| `RTK_HERMES_BACKENDS` | `local` | Comma-separated; `local`, `local,ssh`, or `all` |

> **Note:** `RTK_HERMES_BACKENDS` defaults to `local` — SSH and Docker backends are excluded by default since they may not have `rtk` installed on the remote host. Set `RTK_HERMES_BACKENDS=all` if all backends have RTK available.

### Verification inside the container

```bash
rtk --version
rtk rewrite "git status"     # test rewrite mode works
rtk gain                     # token savings dashboard
```

### Troubleshooting

- If RTK is not rewriting commands, check: `env | grep RTK_HERMES_MODE` (should be `rewrite`)
- If the plugin is not loaded, verify `~/.hermes/config.yaml` has `rtk-rewrite` under `plugins.enabled`
- The plugin is designed to **fail open** — if RTK binary is missing, times out, or crashes, the original command runs unchanged
- Check Hermes logs for lines mentioning `rtk_hermes` or `rtk-rewrite`

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
node -e 'const fs=require("fs"), path=require("path"), cp=require("child_process"); const root=cp.execSync("npm root -g", {encoding:"utf8"}).trim(); const pkg=JSON.parse(fs.readFileSync(path.join(root, "clawmem", "package.json"), "utf8")); console.log(`clawmem ${pkg.version}`)'
clawmem doctor
clawmem status
clawmem collection list
```

## Presentation and OCR boundaries

The base Hermes image already ships generic `powerpoint` and `ocr-and-documents` skills, but this image does **not** currently promise the full runtime dependency set implied by every path in those skills.

Current recommendation:
- use `officecli` for precise edits to existing `.docx/.xlsx/.pptx`
- use `presentation-tools` (ppt-master branch) for generating a full new editable deck from source material
- use bundled `powerpoint` skill primarily as an analysis/editing reference for existing `.pptx`, not as proof that `markitdown`, `pptxgenjs`, and `soffice` are all bundled here
- use `ocr-and-documents` for routing OCR-heavy requests, but remember this image intentionally does **not** bundle PaddleOCR or marker-pdf-scale heavy OCR stacks

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
curl http://127.0.0.1:7438/health
# If CLAWMEM_API_TOKEN is set:
# curl -H "Authorization: Bearer <clawmem-api-token>" http://127.0.0.1:7438/health
```

## Build and publish

The workflow publishes to GHCR as:

- `ghcr.io/<owner>/hermes-office:latest`
- `ghcr.io/<owner>/hermes-office:<hermes-agent-version>`

Triggers:

- push to `main` or `master` affecting `Dockerfile`, `.dockerignore`, workflow, `README.md`, `docker/**`, `deploy/**`, or `skills/**`
- daily scheduled check
- manual `workflow_dispatch`

## Notes

- The scheduled workflow currently checks whether the **base Hermes image** changed, just like `hermes-matrix`.
- Manual dispatch can be used to rebuild after updating pinned upstream versions.
- `PaddleOCR` is intentionally **not** bundled here; you said it will be deployed separately on another server later.
- `unipdf-cli` was intentionally removed because it requires runtime licensing; the image now prefers the open-source stack of `pdfcpu + qpdf + poppler-utils`.
- ClawMem's Hermes plugin currently talks to `clawmem serve` on `127.0.0.1:${CLAWMEM_SERVE_PORT}`; that is why this image runs the REST sidecar locally even when model inference is remote.
- If needed later, upstream-change detection for OfficeCLI releases, PPT Master commits, pdfcpu releases, Docling versions, Bun, and ClawMem versions can be added.
