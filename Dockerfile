ARG HERMES_AGENT_VERSION=v2026.8.3
ARG HERMES_OFFICE_VERSION=${HERMES_AGENT_VERSION}
FROM nousresearch/hermes-agent:${HERMES_AGENT_VERSION}

ARG DEBIAN_FRONTEND=noninteractive
ARG OFFICECLI_VERSION=v1.0.143
ARG OFFICECLI_ASSET=officecli-linux-x64
ARG OFFICECLI_REPO=iOfficeAI/OfficeCli
ARG PPT_MASTER_VERSION=v4.3.0
ARG PPT_MASTER_ARCHIVE_URL=https://github.com/hugohe3/ppt-master/archive/refs/tags/${PPT_MASTER_VERSION}.tar.gz
ARG DOCLING_VERSION=2.118.0
ARG TORCH_CPU_WHL=https://download.pytorch.org/whl/cpu/torch-2.13.0%2Bcpu-cp313-cp313-manylinux_2_28_x86_64.whl#sha256=3fbf9c9d1f3c10c2d59d04aca426dee9ccc6ceb32d255c61e93acc3b4f75fae6
ARG TORCHVISION_CPU_WHL=https://download.pytorch.org/whl/cpu/torchvision-0.28.0%2Bcpu-cp313-cp313-manylinux_2_28_x86_64.whl#sha256=c6373ec4c2f922e89f45ac91889404d312ba29a31f205b0ad9a725a3894ca246
ARG PDFCPU_VERSION=0.14.0
ARG PDFCPU_ASSET_URL=https://github.com/pdfcpu/pdfcpu/releases/download/v${PDFCPU_VERSION}/pdfcpu_${PDFCPU_VERSION}_Linux_x86_64.tar.xz
ARG BUN_VERSION=1.3.14
ARG BUN_ASSET_NAME=bun-linux-x64-baseline.zip
ARG BUN_ASSET_URL=https://github.com/oven-sh/bun/releases/download/bun-v${BUN_VERSION}/${BUN_ASSET_NAME}
ARG BUN_SHASUMS_URL=https://github.com/oven-sh/bun/releases/download/bun-v${BUN_VERSION}/SHASUMS256.txt
ARG CLAWMEM_VERSION=0.30.0
ARG RTK_VERSION=v0.44.2
ARG RTK_ASSET=rtk-x86_64-unknown-linux-musl.tar.gz

LABEL org.opencontainers.image.title="hermes-office"
LABEL org.opencontainers.image.description="Hermes Agent image bundled with OfficeCLI, PPT Master, ImageMagick, Docling, pdfcpu, qpdf, poppler-utils, Bun, ClawMem, and RTK"
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
    pkg-config \
    poppler-utils \
    qpdf \
    unzip \
    xz-utils \
    && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL -o /usr/local/bin/officecli \
    "https://github.com/${OFFICECLI_REPO}/releases/download/${OFFICECLI_VERSION}/${OFFICECLI_ASSET}" \
    && chmod +x /usr/local/bin/officecli \
    && officecli --version

RUN curl -fsSL "${PDFCPU_ASSET_URL}" -o /tmp/pdfcpu.tar.xz \
    && tar -xJf /tmp/pdfcpu.tar.xz -C /tmp \
    && install -m 0755 /tmp/pdfcpu_${PDFCPU_VERSION}_Linux_x86_64/pdfcpu /usr/local/bin/pdfcpu \
    && rm -rf /tmp/pdfcpu.tar.xz /tmp/pdfcpu_${PDFCPU_VERSION}_Linux_x86_64

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

COPY skills/ /opt/hermes/skills/
# s6-overlay cont-init.d hook: runs after base stage2 setup (01-hermes-setup),
# handles rtk-rewrite plugin enablement, ClawMem plugin sync, and ClawMem
# sidecar autostart.
COPY docker/cont-init.d/ /etc/cont-init.d/

USER root

# Create venvs as root — chown back to hermes so runtime access works
RUN uv venv /opt/tools/ppt-master/.venv \
    && uv pip install --python /opt/tools/ppt-master/.venv/bin/python --no-cache-dir -r /opt/tools/ppt-master/requirements.txt \
    && mkdir -p /opt/tools/docling \
    && uv venv /opt/tools/docling/.venv \
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
    && pdfcpu version \
    && qpdf --version \
    && pdfinfo -v \
    && if command -v magick >/dev/null 2>&1; then magick -version; else convert -version; fi
