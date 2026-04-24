FROM golang:1.24-bookworm AS unipdf-builder

ARG DEBIAN_FRONTEND=noninteractive
ARG UNIPDF_CLI_VERSION=v0.14.0
ARG UNIPDF_CLI_ARCHIVE_URL=https://codeload.github.com/unidoc/unipdf-cli/tar.gz/${UNIPDF_CLI_VERSION}

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    tar \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /src /out \
    && curl -fsSL "${UNIPDF_CLI_ARCHIVE_URL}" -o /tmp/unipdf-cli.tar.gz \
    && tar -xzf /tmp/unipdf-cli.tar.gz -C /src \
    && mv /src/unipdf-cli-* /src/unipdf-cli \
    && cd /src/unipdf-cli/cmd/unipdf \
    && go build -o /out/unipdf \
    && rm -rf /tmp/unipdf-cli.tar.gz /src/unipdf-cli

FROM nousresearch/hermes-agent:latest

ARG DEBIAN_FRONTEND=noninteractive
ARG OFFICECLI_VERSION=v1.0.54
ARG OFFICECLI_ASSET=officecli-linux-x64
ARG OFFICECLI_REPO=iOfficeAI/OfficeCli
ARG PPT_MASTER_REF=43ee46b61cfc130af91c18be7d807bdb538f6a7e
ARG PPT_MASTER_ARCHIVE_URL=https://codeload.github.com/hugohe3/ppt-master/tar.gz/${PPT_MASTER_REF}
ARG DOCLING_VERSION=2.91.0
ARG UNIPDF_CLI_VERSION=v0.14.0

LABEL org.opencontainers.image.title="hermes-office"
LABEL org.opencontainers.image.description="Hermes Agent image bundled with OfficeCLI, PPT Master, ImageMagick, UniPDF CLI, and Docling"
LABEL org.opencontainers.image.source="https://github.com/Keivry/hermes-office"
LABEL org.opencontainers.image.vendor="Keivry"
LABEL org.opencontainers.image.licenses="Apache-2.0, MIT"

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    imagemagick \
    pandoc \
    && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL -o /usr/local/bin/officecli \
    "https://github.com/${OFFICECLI_REPO}/releases/download/${OFFICECLI_VERSION}/${OFFICECLI_ASSET}" \
    && chmod +x /usr/local/bin/officecli \
    && officecli --version

COPY --from=unipdf-builder /out/unipdf /usr/local/bin/unipdf

RUN mkdir -p /opt/tools \
    && curl -fsSL "${PPT_MASTER_ARCHIVE_URL}" -o /tmp/ppt-master.tar.gz \
    && tar -xzf /tmp/ppt-master.tar.gz -C /opt/tools \
    && mv "/opt/tools/ppt-master-${PPT_MASTER_REF}" /opt/tools/ppt-master \
    && rm -f /tmp/ppt-master.tar.gz

RUN . /opt/hermes/.venv/bin/activate \
    && uv venv /opt/tools/ppt-master/.venv \
    && uv pip install --python /opt/tools/ppt-master/.venv/bin/python --no-cache-dir -r /opt/tools/ppt-master/requirements.txt \
    && mkdir -p /opt/tools/docling \
    && uv venv /opt/tools/docling/.venv \
    && uv pip install --python /opt/tools/docling/.venv/bin/python --no-cache-dir "docling==${DOCLING_VERSION}" \
    && ln -sf /opt/tools/docling/.venv/bin/docling /usr/local/bin/docling

ENV OFFICECLI_SKIP_UPDATE=1
ENV PPT_MASTER_HOME=/opt/tools/ppt-master
ENV PPT_MASTER_VENV=/opt/tools/ppt-master/.venv
ENV DOCLING_HOME=/opt/tools/docling
ENV DOCLING_VENV=/opt/tools/docling/.venv

RUN /opt/tools/ppt-master/.venv/bin/python --version \
    && /opt/tools/ppt-master/.venv/bin/python -c "import pptx, fitz, PIL, requests, bs4; print('ppt-master deps ok')" \
    && /opt/tools/docling/.venv/bin/python --version \
    && /opt/tools/docling/.venv/bin/docling --version \
    && unipdf version \
    && if command -v magick >/dev/null 2>&1; then magick -version; else convert -version; fi
