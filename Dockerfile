ARG HERMES_AGENT_VERSION=v2026.8.31
ARG HERMES_OFFICE_VERSION=${HERMES_AGENT_VERSION}
FROM nousresearch/hermes-agent:${HERMES_AGENT_VERSION}

ARG DEBIAN_FRONTEND=noninteractive
ARG OFFICECLI_VERSION=v1.0.147
ARG OFFICECLI_ASSET=officecli-linux-x64
ARG OFFICECLI_REPO=iOfficeAI/OfficeCli
ARG PPT_MASTER_VERSION=v6.2.0
ARG PPT_MASTER_ARCHIVE_URL=https://github.com/hugohe3/ppt-master/archive/refs/tags/${PPT_MASTER_VERSION}.tar.gz
ARG DOCLING_VERSION=2.124.0
ARG TORCH_CPU_WHL=https://download.pytorch.org/whl/cpu/torch-2.13.0%2Bcpu-cp313-cp313-manylinux_2_28_x86_64.whl#sha256=3fbf9c9d1f3c10c2d59d04aca426dee9ccc6ceb32d255c61e93acc3b4f75fae6
ARG TORCHVISION_CPU_WHL=https://download.pytorch.org/whl/cpu/torchvision-0.28.0%2Bcpu-cp313-cp313-manylinux_2_28_x86_64.whl#sha256=c6373ec4c2f922e89f45ac91889404d312ba29a31f205b0ad9a725a3894ca246
ARG PDFCPU_VERSION=0.15.0
ARG PDFCPU_ASSET_URL=https://github.com/pdfcpu/pdfcpu/releases/download/v${PDFCPU_VERSION}/pdfcpu_${PDFCPU_VERSION}_Linux_x86_64.tar.xz
ARG BUN_VERSION=1.4.0
ARG BUN_ASSET_NAME=bun-linux-x64-baseline.zip
ARG BUN_ASSET_URL=https://github.com/oven-sh/bun/releases/download/bun-v${BUN_VERSION}/${BUN_ASSET_NAME}
ARG BUN_SHASUMS_URL=https://github.com/oven-sh/bun/releases/download/bun-v${BUN_VERSION}/SHASUMS256.txt
ARG CLAWMEM_VERSION=0.37.0
ARG RTK_VERSION=v0.47.0
ARG RTK_ASSET=rtk-x86_64-unknown-linux-musl.tar.gz
ARG GH_VERSION=v2.99.0
ARG GH_ASSET=gh_2.99.0_linux_amd64.tar.gz
ARG GH_ASSET_URL=https://github.com/cli/cli/releases/download/${GH_VERSION}/${GH_ASSET}
# Official sqlite3 CLI matching the base image's bundled libsqlite3 3.53.4 in
# /usr/local/lib. Debian's /usr/bin/sqlite3 (compiled against 3.46.1) resolves
# /usr/local/lib first via ld.so.conf.d and refuses to run with "header and
# source version mismatch". Pin the matching tools zip under /usr/local/bin.
ARG SQLITE_VERSION=3530400
ARG SQLITE_ASSET_URL=https://www.sqlite.org/2026/sqlite-tools-linux-x64-${SQLITE_VERSION}.zip
ARG SQLITE_ASSET_SHA256=7a6f4d1720e4bc13faa3d934bfce37b816a496c0a2480deacd64cfd8be6cf224

LABEL org.opencontainers.image.title="hermes-office"
LABEL org.opencontainers.image.description="Hermes Agent image bundled with OfficeCLI, PPT Master, ImageMagick, Docling, pdfcpu, qpdf, poppler-utils, Bun, ClawMem, RTK, and common CLI utilities (gh, jq, less, ...)"
LABEL org.opencontainers.image.source="https://github.com/Keivry/hermes-office"
LABEL org.opencontainers.image.vendor="Keivry"
LABEL org.opencontainers.image.licenses="Apache-2.0, MIT"

ARG HERMES_OFFICE_VERSION
ARG HERMES_AGENT_VERSION

LABEL org.opencontainers.image.version="${HERMES_OFFICE_VERSION}"

USER root

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    imagemagick \
    libcairo2-dev \
    libicu-dev \
    pandoc \
    patch \
    pkg-config \
    poppler-utils \
    qpdf \
    unzip \
    xz-utils \
    dnsutils \
    file \
    git-lfs \
    iproute2 \
    jq \
    less \
    lsof \
    mtr \
    net-tools \
    netcat-openbsd \
    rsync \
    sqlite3 \
    strace \
    traceroute \
    tree \
    wget \
    yq \
    zip \
    zstd \
    && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL -o /usr/local/bin/officecli \
    "https://github.com/${OFFICECLI_REPO}/releases/download/${OFFICECLI_VERSION}/${OFFICECLI_ASSET}" \
    && chmod +x /usr/local/bin/officecli \
    && officecli --version

RUN curl -fsSL "${PDFCPU_ASSET_URL}" -o /tmp/pdfcpu.tar.xz \
    && tar -xJf /tmp/pdfcpu.tar.xz -C /tmp \
    && install -m 0755 /tmp/pdfcpu_${PDFCPU_VERSION}_Linux_x86_64/pdfcpu /usr/local/bin/pdfcpu \
    && rm -rf /tmp/pdfcpu.tar.xz /tmp/pdfcpu_${PDFCPU_VERSION}_Linux_x86_64

RUN curl -fsSL "${GH_ASSET_URL}" -o /tmp/gh.tar.gz \
    && tar -xzf /tmp/gh.tar.gz -C /tmp \
    && install -m 0755 "/tmp/gh_${GH_VERSION#v}_linux_amd64/bin/gh" /usr/local/bin/gh \
    && rm -rf /tmp/gh.tar.gz "/tmp/gh_${GH_VERSION#v}_linux_amd64" \
    && gh --version

RUN curl -fsSL "${BUN_ASSET_URL}" -o "/tmp/${BUN_ASSET_NAME}" \
    && curl -fsSL "${BUN_SHASUMS_URL}" -o /tmp/SHASUMS256.txt \
    && grep "  ${BUN_ASSET_NAME}$" /tmp/SHASUMS256.txt > /tmp/bun.sha256 \
    && (cd /tmp && sha256sum -c bun.sha256) \
    && unzip -q "/tmp/${BUN_ASSET_NAME}" -d /tmp \
    && install -m 0755 /tmp/bun-linux-x64-baseline/bun /usr/local/bin/bun \
    && rm -rf "/tmp/${BUN_ASSET_NAME}" /tmp/SHASUMS256.txt /tmp/bun.sha256 /tmp/bun-linux-x64-baseline \
    && bun --version

RUN curl -fsSL "https://github.com/rtk-ai/rtk/releases/download/${RTK_VERSION}/${RTK_ASSET}" -o /tmp/rtk.tar.gz \
    && tar -xzf /tmp/rtk.tar.gz -C /tmp \
    && install -m 0755 /tmp/rtk /usr/local/bin/rtk \
    && rm -rf /tmp/rtk.tar.gz /tmp/rtk \
    && rtk --version

# Replace the broken Debian sqlite3 CLI with the official 3.53.4 tools zip so
# the CLI version matches the /usr/local/lib libsqlite3 the base image ships.
RUN curl -fsSL "${SQLITE_ASSET_URL}" -o /tmp/sqlite-tools.zip \
    && echo "${SQLITE_ASSET_SHA256}  /tmp/sqlite-tools.zip" | sha256sum -c - \
    && unzip -q /tmp/sqlite-tools.zip -d /tmp/sqlite-tools \
    && install -m 0755 /tmp/sqlite-tools/sqlite3 /usr/local/bin/sqlite3 \
    && rm -rf /tmp/sqlite-tools.zip /tmp/sqlite-tools \
    && sqlite3 --version

RUN npm install -g --unsafe-perm --no-fund --no-audit "clawmem@${CLAWMEM_VERSION}" \
    && node -e 'const fs=require("fs"), path=require("path"), cp=require("child_process"); const root=cp.execSync("npm root -g", {encoding:"utf8"}).trim(); const pkg=JSON.parse(fs.readFileSync(path.join(root, "clawmem", "package.json"), "utf8")); console.log(`clawmem ${pkg.version}`)'

RUN mkdir -p /opt/tools /opt/tools/clawmem-plugin \
    && CLAWMEM_NODE_ROOT="$(npm root -g)" \
    && curl -fsSL "${PPT_MASTER_ARCHIVE_URL}" -o /tmp/ppt-master.tar.gz \
    && tar -xzf /tmp/ppt-master.tar.gz -C /opt/tools \
    && mv "/opt/tools/ppt-master-${PPT_MASTER_VERSION#v}" /opt/tools/ppt-master \
    && cp -R "${CLAWMEM_NODE_ROOT}/clawmem/src/hermes/." /opt/tools/clawmem-plugin/ \
    && rm -f /tmp/ppt-master.tar.gz \
    && chown -R hermes:hermes /opt/tools

# Hermes venv was created during base image build as root;
# make it writable so rtk-hermes and future pip-installed plugins
# can be added under USER hermes.
RUN chown -R hermes:hermes /opt/hermes/.venv

# Install rtk-hermes into Hermes venv as root (venv may be root-owned in v0.18.0 base)
RUN uv pip install --python /opt/hermes/.venv/bin/python --no-cache-dir \
    "rtk-hermes==1.2.3"

# ── Upstream hotfix patches ──────────────────────────────────────────────
# Apply pending upstream fixes from patches/ (unified diff, `patch -p1`).
# Each .patch is applied in lexicographic order against /opt/hermes; a failing
# patch aborts the build so a half-patched image never ships. Remove a patch
# file once the fix is merged upstream and HERMES_AGENT_VERSION is bumped.
# As of v2026.8.31: 009/010 (empty tool_calls dedup + wire boundary), 012
# (gateway stderr timestamps) and 013 (update_cmd SyntaxWarning) merged
# upstream — dropped. Remaining 9 still needed (017 vendors post-tag
# upstream PR #101864; 018 is hermes-office specific):
# 004 = environment-specific (NOT upstream): narrow the #62151 direct_api_call
#   workaround to openrouter/nous only — custom providers (e.g. deepseek)
#   must keep streaming to avoid ServerDisconnectedError behind proxies
#   (#71268). Keep — upstream still forces all cron/delegation inline.
# 007 = upstream #77100 (open): Matrix adapter loop-mismatch bridge — keep
#   until #77100 merges upstream.
# 008 = upstream #44347 (open): file_read toolset (read-only subset of file:
#   read_file + search_files, NO write/patch) — sandboxed read-only agents
#   (skill-audit) can inspect files without a write path. Trimmed to the 3
#   runtime files (toolsets.py / hermes_cli/setup.py / hermes_cli/tools_config.py);
#   PR tests/website hunks excluded (not shipped in the production image —
#   including them makes `patch` fail and abort the build). Keep until #44347
#   merges upstream; then drop and bump HERMES_AGENT_VERSION.
# 011 = upstream #85207 (open): gateway restart mid-turn can spawn TWO parallel
#   conversation loops on one session (detached restart overlap), duplicating
#   the whole history and delivering divergent finals. Durable active-turn
#   marker now records the owning gateway PID; boot recovery/auto-resume refuse
#   to start a second loop while the owner is alive (PR #85285, open). Keep
#   until #85285 merges upstream.
# 014 = upstream #82816/#85713 (open): title_generator unconditionally sent
#   OpenAI-only response_format json_schema strict → Console Go / DeepSeek /
#   Anthropic all 400 ("This response_format type is unavailable now") on every
#   fresh session. This patch drops response_format entirely; _extract_title_text
#   already falls back through JSON-dict → loose regex → prose+think-strip, so
#   titles still work. Keep until #85713 (retry-cascade) merges upstream.
# 015 = upstream #78888 (open): checkpoint_manager DEFAULT_EXCLUDES missing
#   node-compile-cache/ — the desktop/TUI launcher writes this cache (can be
#   root-owned) into <workdir>/tmp/node-compile-cache/, so `git add -A` aborts
#   with Permission denied (rc=128) and affected workdirs get zero checkpoints.
#   Adds the exclude + _ensure_store_excludes() so existing stores also pick it
#   up. Trimmed to tools/checkpoint_manager.py (PR tests excluded). Keep until
#   #78929/#78944 merge upstream.
# 016 = fix(checkpoints): bare-repo self-heal for `fatal: not a git repository:
#   '/.../checkpoints/store'` after `git gc --prune=now` deletes empty
#   refs/heads/ & branches/ (bare repo with only packed-refs, Git 2.34+).
#   Observed as `git add -A` spamming ERROR after every auto-prune (24h) —
#   _repair_bare_repo_dirs() existed but was only called AFTER gc, never
#   BEFORE the next checkpoint. This patch adds proactive repair before every
#   git call (_run_git) + retry-on-fatal + early repair in _init_store.
#   Refs: #65349 (concurrent gc), #79334/#79335 (size-cap loop), #83036
#   (GC tmp packs/corruption), local 015/#78888. Keep until upstream merges
#   the bare-repo-dir fix. Verified 2026-09-03: all 9 apply cleanly against
#   v2026.8.31 in lexicographic order (016's hunk 3 depends on 015 having
#   been applied first, 018 depends on 017 — do NOT dry-run 016/018 standalone).
# 017 = upstream PR #101864 (merged to main after v2026.8.31, in no tag yet):
#   x-opencode-session affinity header on every OpenCode request (main turn
#   on all transports + auxiliary calls). Vendored trimmed to runtime files
#   (new agent/opencode_affinity.py + chat_completion_helpers rename+wrap
#   adapted to the tag's function head + auxiliary_client forwarding);
#   upstream tests/website hunks excluded (not shipped in the image). Drop
#   when the base tag includes #101864.
# 018 = hermes-office specific (NOT upstream): named custom providers
#   fronting the relay (custom:opencode -> proxy IP) flatten to provider
#   "custom" at runtime, so 017's target check misses on both signals;
#   thread requested_provider through and strip the custom: prefix before
#   the family check (opencode -> opencode-zen via existing alias). Main
#   turn uses agent.requested_provider, aux uses the turn-context record.
#   Revisit if upstream covers custom providers behind proxies.
COPY patches/ /tmp/hermes-patches/
RUN set -eux; \
    if ls /tmp/hermes-patches/*.patch >/dev/null 2>&1; then \
        for p in /tmp/hermes-patches/*.patch; do \
            echo "==> Applying $(basename "$p")"; \
            (cd /opt/hermes && patch -p1 < "$p"); \
        done; \
    fi; \
    rm -rf /tmp/hermes-patches

COPY skills/ /opt/hermes/skills/
# s6-overlay cont-init.d hook: runs after base stage2 setup (01-hermes-setup),
# handles rtk-rewrite plugin enablement, ClawMem plugin sync, and ClawMem
# sidecar autostart.
COPY docker/cont-init.d/ /etc/cont-init.d/

USER root

# Create venvs as root — chown back to hermes so runtime access works.
# NOTE 1: uv 0.11+ in base v2026.8.19 defaults to downloading CPython 3.11 when
#         no --python is given, which breaks the cp313 torch wheels. Pin 3.13.
# NOTE 2: base v2026.8.19 sets [tool.uv] exclude-newer = "14 days" in
#         /opt/hermes/pyproject.toml. Since the Dockerfile inherits WORKDIR
#         /opt/hermes, uv resolves that config and refuses packages published
#         in the last 14 days (e.g. docling 2.124.0). Run from /tmp to bypass.
RUN cd /tmp \
    && uv venv --python 3.13 /opt/tools/ppt-master/.venv \
    && uv pip install --python /opt/tools/ppt-master/.venv/bin/python --no-cache-dir -r /opt/tools/ppt-master/requirements.txt \
    && mkdir -p /opt/tools/docling \
    && uv venv --python 3.13 /opt/tools/docling/.venv \
    && uv pip install --python /opt/tools/docling/.venv/bin/python --no-cache-dir \
        "${TORCH_CPU_WHL}" "${TORCHVISION_CPU_WHL}" \
    && uv pip install --python /opt/tools/docling/.venv/bin/python --no-cache-dir \
        "docling==${DOCLING_VERSION}"

# Root-owned venv files under /opt/tools — chown to hermes for runtime access
RUN chown -R hermes:hermes /opt/tools

ENV OFFICECLI_SKIP_UPDATE=1
ENV PPT_MASTER_HOME=/opt/tools/ppt-master
ENV PPT_MASTER_VENV=/opt/tools/ppt-master/.venv
ENV DOCLING_HOME=/opt/tools/docling
ENV DOCLING_VENV=/opt/tools/docling/.venv
ENV CLAWMEM_BIN=/usr/local/bin/clawmem
ENV CLAWMEM_SERVE_PORT=7438
ENV CLAWMEM_SERVE_MODE=external
ENV CLAWMEM_PROFILE=balanced
ENV CLAWMEM_NO_LOCAL_MODELS=true
ENV INDEX_PATH=/opt/data/state/clawmem/index.sqlite
ENV CLAWMEM_FOCUS_ROOT=/opt/data/state/clawmem/sessions
ENV HERMES_CLAWMEM_PLUGIN_SOURCE=/opt/tools/clawmem-plugin
ENV HERMES_CLAWMEM_SYNC_PLUGIN=true
ENV HERMES_CLAWMEM_AUTOSTART_SERVE=true
ENV PATH="/opt/tools/docling/.venv/bin:${PATH}"

RUN /opt/tools/ppt-master/.venv/bin/python --version \
    && /opt/tools/ppt-master/.venv/bin/python -c "import pptx, fitz, PIL, requests, bs4; print('ppt-master deps ok')" \
    && /opt/tools/docling/.venv/bin/python --version \
    && /opt/tools/docling/.venv/bin/docling --version \
    && bun --version \
    && node -e 'const fs=require("fs"), path=require("path"), cp=require("child_process"); const root=cp.execSync("npm root -g", {encoding:"utf8"}).trim(); const pkg=JSON.parse(fs.readFileSync(path.join(root, "clawmem", "package.json"), "utf8")); console.log(`clawmem ${pkg.version}`)' \
    && rtk --version \
    && gh --version \
    && git lfs version \
    && pdfcpu version \
    && qpdf --version \
    && pdfinfo -v \
    && if command -v magick >/dev/null 2>&1; then magick -version; else convert -version; fi
