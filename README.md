# hermes-office

A `nousresearch/hermes-agent`-based Docker image bundled with:

- [OfficeCLI](https://github.com/iOfficeAI/OfficeCLI)
- [PPT Master](https://github.com/hugohe3/ppt-master)

This repository reuses the same GitHub Actions build/publish pattern as `Keivry/hermes-matrix`, but targets Office document automation and editable PPT generation.

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

## Included extra system packages

The image only adds the packages that are still needed beyond the official Hermes base image:

- `curl`
- `pandoc`

`git` and `nodejs` are already present in the upstream `nousresearch/hermes-agent` image, so this repo does not reinstall them.

## Runtime environment

Environment variables baked into the image:

- `OFFICECLI_SKIP_UPDATE=1`
- `PPT_MASTER_HOME=/opt/tools/ppt-master`
- `PPT_MASTER_VENV=/opt/tools/ppt-master/.venv`

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
- If needed later, upstream-change detection for OfficeCLI releases and PPT Master commits can be added.
