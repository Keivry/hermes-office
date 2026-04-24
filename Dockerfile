FROM nousresearch/hermes-agent:latest

ARG DEBIAN_FRONTEND=noninteractive
ARG OFFICECLI_VERSION=v1.0.54
ARG OFFICECLI_ASSET=officecli-linux-x64
ARG OFFICECLI_REPO=iOfficeAI/OfficeCli
ARG PPT_MASTER_REF=43ee46b61cfc130af91c18be7d807bdb538f6a7e
ARG PPT_MASTER_ARCHIVE_URL=https://codeload.github.com/hugohe3/ppt-master/tar.gz/${PPT_MASTER_REF}

LABEL org.opencontainers.image.title="hermes-office"
LABEL org.opencontainers.image.description="Hermes Agent image bundled with OfficeCLI and PPT Master"
LABEL org.opencontainers.image.source="https://github.com/Keivry/hermes-office"
LABEL org.opencontainers.image.vendor="Keivry"
LABEL org.opencontainers.image.licenses="Apache-2.0, MIT"

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    pandoc \
    && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL -o /usr/local/bin/officecli \
    "https://github.com/${OFFICECLI_REPO}/releases/download/${OFFICECLI_VERSION}/${OFFICECLI_ASSET}" \
    && chmod +x /usr/local/bin/officecli \
    && officecli --version

RUN mkdir -p /opt/tools \
    && curl -fsSL "${PPT_MASTER_ARCHIVE_URL}" -o /tmp/ppt-master.tar.gz \
    && tar -xzf /tmp/ppt-master.tar.gz -C /opt/tools \
    && mv "/opt/tools/ppt-master-${PPT_MASTER_REF}" /opt/tools/ppt-master \
    && rm -f /tmp/ppt-master.tar.gz

RUN . /opt/hermes/.venv/bin/activate \
    && uv venv /opt/tools/ppt-master/.venv \
    && uv pip install --python /opt/tools/ppt-master/.venv/bin/python --no-cache-dir -r /opt/tools/ppt-master/requirements.txt

ENV OFFICECLI_SKIP_UPDATE=1
ENV PPT_MASTER_HOME=/opt/tools/ppt-master
ENV PPT_MASTER_VENV=/opt/tools/ppt-master/.venv

RUN /opt/tools/ppt-master/.venv/bin/python --version \
    && /opt/tools/ppt-master/.venv/bin/python -c "import pptx, fitz, PIL, requests, bs4; print('ppt-master deps ok')"
