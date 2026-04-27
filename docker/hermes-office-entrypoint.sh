#!/bin/bash
# hermes-office entrypoint: base Hermes bootstrap + ClawMem plugin sync + local ClawMem REST sidecar.
set -euo pipefail

HERMES_HOME="${HERMES_HOME:-/opt/data}"
INSTALL_DIR="/opt/hermes"
export HERMES_HOME
export HOME="${HOME:-$HERMES_HOME/home}"

# --- Privilege dropping via gosu ---
if [ "$(id -u)" = "0" ]; then
    if [ -n "${HERMES_UID:-}" ] && [ "$HERMES_UID" != "$(id -u hermes)" ]; then
        echo "Changing hermes UID to $HERMES_UID"
        usermod -u "$HERMES_UID" hermes
    fi

    if [ -n "${HERMES_GID:-}" ] && [ "$HERMES_GID" != "$(id -g hermes)" ]; then
        echo "Changing hermes GID to $HERMES_GID"
        groupmod -o -g "$HERMES_GID" hermes 2>/dev/null || true
    fi

    actual_hermes_uid=$(id -u hermes)
    needs_chown=false
    if [ -n "${HERMES_UID:-}" ] && [ "$HERMES_UID" != "10000" ]; then
        needs_chown=true
    elif [ "$(stat -c %u "$HERMES_HOME" 2>/dev/null || echo '')" != "$actual_hermes_uid" ]; then
        needs_chown=true
    fi
    if [ "$needs_chown" = true ]; then
        echo "Fixing ownership of $HERMES_HOME to hermes ($actual_hermes_uid)"
        chown -R hermes:hermes "$HERMES_HOME" 2>/dev/null || \
            echo "Warning: chown failed (rootless container?) — continuing anyway"
    fi

    if [ -f "$HERMES_HOME/config.yaml" ]; then
        chown hermes:hermes "$HERMES_HOME/config.yaml" 2>/dev/null || true
        chmod 640 "$HERMES_HOME/config.yaml" 2>/dev/null || true
    fi

    echo "Dropping root privileges"
    exec gosu hermes "$0" "$@"
fi

# --- Running as hermes from here ---
source "${INSTALL_DIR}/.venv/bin/activate"

mkdir -p \
    "$HERMES_HOME"/{cron,sessions,logs,hooks,memories,skills,skins,plans,workspace,home,plugins,clawmem-transcripts} \
    "$HERMES_HOME/runtime/clawmem"/{tmp,debug} \
    "$HERMES_HOME/state/clawmem/sessions" \
    "$HOME"

if [ ! -f "$HERMES_HOME/.env" ]; then
    cp "$INSTALL_DIR/.env.example" "$HERMES_HOME/.env"
fi

if [ ! -f "$HERMES_HOME/config.yaml" ]; then
    cp "$INSTALL_DIR/cli-config.yaml.example" "$HERMES_HOME/config.yaml"
fi

if [ ! -f "$HERMES_HOME/SOUL.md" ]; then
    cp "$INSTALL_DIR/docker/SOUL.md" "$HERMES_HOME/SOUL.md"
fi

if [ -d "$INSTALL_DIR/skills" ]; then
    python3 "$INSTALL_DIR/tools/skills_sync.py"
fi

if [ "${HERMES_CLAWMEM_SYNC_PLUGIN:-true}" = "true" ] && [ -d "${HERMES_CLAWMEM_PLUGIN_SOURCE:-}" ]; then
    rm -rf "$HERMES_HOME/plugins/clawmem"
    mkdir -p "$HERMES_HOME/plugins/clawmem"
    cp -R "${HERMES_CLAWMEM_PLUGIN_SOURCE}/." "$HERMES_HOME/plugins/clawmem/"
fi

export INDEX_PATH="${INDEX_PATH:-$HERMES_HOME/state/clawmem/index.sqlite}"
export CLAWMEM_FOCUS_ROOT="${CLAWMEM_FOCUS_ROOT:-$HERMES_HOME/state/clawmem/sessions}"

if [ "${CLAWMEM_SERVE_MODE:-external}" = "external" ] && [ "${CLAWMEM_NO_LOCAL_MODELS:-true}" = "true" ]; then
    missing_remote_envs=()
    for var_name in CLAWMEM_EMBED_URL CLAWMEM_LLM_URL CLAWMEM_RERANK_URL; do
        if [ -z "${!var_name:-}" ]; then
            missing_remote_envs+=("$var_name")
        fi
    done
    if [ ${#missing_remote_envs[@]} -gt 0 ]; then
        printf 'Missing required ClawMem remote model env(s): %s\n' "${missing_remote_envs[*]}" >&2
        printf 'Set remote llama.cpp endpoints before starting Hermes when CLAWMEM_SERVE_MODE=external and CLAWMEM_NO_LOCAL_MODELS=true.\n' >&2
        exit 1
    fi
fi

if [ "${HERMES_CLAWMEM_AUTOSTART_SERVE:-true}" = "true" ]; then
    if ! python3 - <<'PY'
import os, sys, urllib.request
port = os.environ.get("CLAWMEM_SERVE_PORT", "7438")
token = os.environ.get("CLAWMEM_API_TOKEN", "")
req = urllib.request.Request(f"http://127.0.0.1:{port}/health")
if token:
    req.add_header("Authorization", f"Bearer {token}")
try:
    with urllib.request.urlopen(req, timeout=1):
        sys.exit(0)
except Exception:
    sys.exit(1)
PY
    then
        nohup "$CLAWMEM_BIN" serve --host 127.0.0.1 --port "$CLAWMEM_SERVE_PORT" \
            >"$HERMES_HOME/runtime/clawmem/debug/serve.log" 2>&1 &
        python3 - <<'PY'
import os, sys, time, urllib.request
port = os.environ.get("CLAWMEM_SERVE_PORT", "7438")
token = os.environ.get("CLAWMEM_API_TOKEN", "")
for _ in range(30):
    req = urllib.request.Request(f"http://127.0.0.1:{port}/health")
    if token:
        req.add_header("Authorization", f"Bearer {token}")
    try:
        with urllib.request.urlopen(req, timeout=1):
            sys.exit(0)
    except Exception:
        time.sleep(0.5)
sys.exit(1)
PY
    fi
fi

if [ $# -gt 0 ] && command -v "$1" >/dev/null 2>&1; then
    exec "$@"
fi
exec hermes "$@"
