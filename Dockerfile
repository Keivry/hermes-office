FROM nousresearch/hermes-agent:latest

ARG DEBIAN_FRONTEND=noninteractive
ARG OFFICECLI_VERSION=v1.0.54
ARG OFFICECLI_ASSET=officecli-linux-x64
ARG OFFICECLI_REPO=iOfficeAI/OfficeCli
ARG PPT_MASTER_REF=43ee46b61cfc130af91c18be7d807bdb538f6a7e
ARG PPT_MASTER_ARCHIVE_URL=https://codeload.github.com/hugohe3/ppt-master/tar.gz/${PPT_MASTER_REF}
ARG DOCLING_VERSION=2.89.0
ARG TORCH_CPU_WHL=https://download.pytorch.org/whl/cpu/torch-2.10.0%2Bcpu-cp313-cp313-manylinux_2_28_x86_64.whl#sha256=8d316e5bf121f1eab1147e49ad0511a9d92e4c45cc357d1ab0bee440da71a095
ARG TORCHVISION_CPU_WHL=https://download.pytorch.org/whl/cpu/torchvision-0.25.0%2Bcpu-cp313-cp313-manylinux_2_28_x86_64.whl#sha256=90eec299e1f82cfaf080ccb789df3838cb9a54b57e2ebe33852cd392c692de5c
ARG PDFCPU_VERSION=0.12.0
ARG PDFCPU_ASSET_URL=https://github.com/pdfcpu/pdfcpu/releases/download/v${PDFCPU_VERSION}/pdfcpu_${PDFCPU_VERSION}_Linux_x86_64.tar.xz
ARG BUN_VERSION=1.3.13
ARG BUN_ASSET_NAME=bun-linux-x64-baseline.zip
ARG BUN_ASSET_URL=https://github.com/oven-sh/bun/releases/download/bun-v${BUN_VERSION}/${BUN_ASSET_NAME}
ARG BUN_SHASUMS_URL=https://github.com/oven-sh/bun/releases/download/bun-v${BUN_VERSION}/SHASUMS256.txt
ARG CLAWMEM_VERSION=0.10.1

LABEL org.opencontainers.image.title="hermes-office"
LABEL org.opencontainers.image.description="Hermes Agent image bundled with OfficeCLI, PPT Master, ImageMagick, Docling, pdfcpu, qpdf, poppler-utils, Bun, and ClawMem"
LABEL org.opencontainers.image.source="https://github.com/Keivry/hermes-office"
LABEL org.opencontainers.image.vendor="Keivry"
LABEL org.opencontainers.image.licenses="Apache-2.0, MIT"

USER root

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    imagemagick \
    libcairo2-dev \
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

RUN npm install -g --unsafe-perm --no-fund --no-audit "clawmem@${CLAWMEM_VERSION}" \
    && clawmem --version

RUN mkdir -p /opt/tools /opt/tools/clawmem-plugin \
    && CLAWMEM_NODE_ROOT="$(npm root -g)" \
    && curl -fsSL "${PPT_MASTER_ARCHIVE_URL}" -o /tmp/ppt-master.tar.gz \
    && tar -xzf /tmp/ppt-master.tar.gz -C /opt/tools \
    && mv "/opt/tools/ppt-master-${PPT_MASTER_REF}" /opt/tools/ppt-master \
    && cp -R "${CLAWMEM_NODE_ROOT}/clawmem/src/hermes/." /opt/tools/clawmem-plugin/ \
    && rm -f /tmp/ppt-master.tar.gz \
    && chown -R hermes:hermes /opt/tools

COPY docker/hermes-office-entrypoint.sh /usr/local/bin/hermes-office-entrypoint.sh
RUN chmod 0755 /usr/local/bin/hermes-office-entrypoint.sh

USER hermes

RUN uv venv /opt/tools/ppt-master/.venv \
    && uv pip install --python /opt/tools/ppt-master/.venv/bin/python --no-cache-dir -r /opt/tools/ppt-master/requirements.txt \
    && mkdir -p /opt/tools/docling \
    && uv venv /opt/tools/docling/.venv \
    && uv pip install --python /opt/tools/docling/.venv/bin/python --no-cache-dir \
        "${TORCH_CPU_WHL}" "${TORCHVISION_CPU_WHL}" \
    && uv pip install --python /opt/tools/docling/.venv/bin/python --no-cache-dir \
        "docling==${DOCLING_VERSION}"

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
    && clawmem --version \
    && pdfcpu version \
    && qpdf --version \
    && pdfinfo -v \
    && if command -v magick >/dev/null 2>&1; then magick -version; else convert -version; fi

ENTRYPOINT ["/usr/bin/tini", "-g", "--", "/usr/local/bin/hermes-office-entrypoint.sh"]
