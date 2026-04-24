FROM nousresearch/hermes-agent:latest

ARG DEBIAN_FRONTEND=noninteractive
ARG OFFICECLI_VERSION=v1.0.54
ARG OFFICECLI_ASSET=officecli-linux-x64
ARG OFFICECLI_REPO=iOfficeAI/OfficeCli
ARG PPT_MASTER_REF=43ee46b61cfc130af91c18be7d807bdb538f6a7e
ARG PPT_MASTER_ARCHIVE_URL=https://codeload.github.com/hugohe3/ppt-master/tar.gz/${PPT_MASTER_REF}
ARG DOCLING_VERSION=2.91.0
ARG PDFCPU_VERSION=0.12.0
ARG PDFCPU_ASSET_URL=https://github.com/pdfcpu/pdfcpu/releases/download/v${PDFCPU_VERSION}/pdfcpu_${PDFCPU_VERSION}_Linux_x86_64.tar.xz

LABEL org.opencontainers.image.title="hermes-office"
LABEL org.opencontainers.image.description="Hermes Agent image bundled with OfficeCLI, PPT Master, ImageMagick, Docling, pdfcpu, qpdf, and poppler-utils"
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

RUN mkdir -p /opt/tools \
    && curl -fsSL "${PPT_MASTER_ARCHIVE_URL}" -o /tmp/ppt-master.tar.gz \
    && tar -xzf /tmp/ppt-master.tar.gz -C /opt/tools \
    && mv "/opt/tools/ppt-master-${PPT_MASTER_REF}" /opt/tools/ppt-master \
    && rm -f /tmp/ppt-master.tar.gz \
    && chown -R hermes:hermes /opt/tools

USER hermes

RUN uv venv /opt/tools/ppt-master/.venv \
    && uv pip install --python /opt/tools/ppt-master/.venv/bin/python --no-cache-dir -r /opt/tools/ppt-master/requirements.txt \
    && mkdir -p /opt/tools/docling \
    && uv venv /opt/tools/docling/.venv \
    && uv pip install --python /opt/tools/docling/.venv/bin/python --no-cache-dir \
        --index-url https://pypi.org/simple \
        --extra-index-url https://download.pytorch.org/whl/cpu \
        --index-strategy unsafe-best-match \
        "docling==${DOCLING_VERSION}"

ENV OFFICECLI_SKIP_UPDATE=1
ENV PPT_MASTER_HOME=/opt/tools/ppt-master
ENV PPT_MASTER_VENV=/opt/tools/ppt-master/.venv
ENV DOCLING_HOME=/opt/tools/docling
ENV DOCLING_VENV=/opt/tools/docling/.venv
ENV PATH="/opt/tools/docling/.venv/bin:${PATH}"

RUN /opt/tools/ppt-master/.venv/bin/python --version \
    && /opt/tools/ppt-master/.venv/bin/python -c "import pptx, fitz, PIL, requests, bs4; print('ppt-master deps ok')" \
    && /opt/tools/docling/.venv/bin/python --version \
    && /opt/tools/docling/.venv/bin/docling --version \
    && pdfcpu version \
    && qpdf --version \
    && pdfinfo -v \
    && if command -v magick >/dev/null 2>&1; then magick -version; else convert -version; fi
