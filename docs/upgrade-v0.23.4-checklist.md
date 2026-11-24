# hermes-office v0.23.3 → v0.23.4 upgrade checklist

Written 2026-11-24, together with the v0.23.4 sweep. Test evidence lives in the Dockerfile
header ("2026-11-24 sweep") and in this repo's git history; this file is the **post-upgrade
check order** — run it top to bottom after the new image is deployed.

- Upstream base: `nousresearch/hermes-agent:v0.23.4`
  (index digest `sha256:ef0650d523ee1b5ab32c779acabc446d9936869a9932591553688a62bcf0c42f`)
- Patch roster: 16 (`007, 008, 011, 014, 015, 016, 018, 032, 035, 036, 037, 038, 039, 040, 041, 042`)
  — **zero retired, zero re-anchored** (16/16 apply at fuzz 0)
- ClawMem patch roster: 6 (`036, 040, 041, 042, 043, 044`), verified against clawmem 0.43.8
  (041's `store.ts` import hunk re-anchored for 0.43.8; the other five unchanged)
- Config schema: **54**, unchanged — `hermes_cli/config_migrations.py` is identical between the
  two tags, so `hermes config migrate` is a no-op for this bump
- Base runtime: python 3.14.9 (build 20261021), node 26.12.1, npm 12.2.2, uv 0.13.5, pnpm 12.15.0
  — identical to v0.23.3; `pm/lock.json` and the base `Dockerfile` are byte-identical across tags

## What upstream changed in this window

v0.23.4 is a patch rollup over v0.23.3: 1,122 non-merge commits, 1,316 files (+96,873/−6,703),
229 merged PRs, 281 closed issues (measured at `8fc03744473`). Upstream deliberately ships a
stub release and defers the curated notes to v0.24.0; the release text names:

- Desktop: streaming/transcript performance, approval cards for sandbox folder/site requests,
  retryable indicator for slow profile switches
- Gateway: `hermes gateway migrate --backends` with a dashboard System card, clients announce
  themselves so plugins can see which client sent a turn, status reporting
- Plugins/CLI: `hermes plugins config`, `hermes dashboard password` without a TTY
- Skills: configurable skill-index description width (`skills.index_desc_limit`, 60–1024)
- Models: Gemini 4 Hydrogen / Neon / Carbon on Nous Portal, OpenRouter and Vertex
- Security: managed-scope config honored by security and URL-safety reads

**None of these removes or replaces a patch target.** Upstream touched only four of the
patch-target files — `cron/scheduler.py`, `gateway/run_startup.py`,
`plugins/platforms/matrix/adapter.py`, `tools/skill_manager_tool.py` — and every change landed
outside the patched hunks.

## 0. Before touching the live container

```bash
cp -a /opt/data/config.yaml /opt/data/config.yaml.bak-$(date +%Y%m%dT%H%M%SZ)
```

Rollback (config only):

```bash
cp -a /opt/data/config.yaml.bak-<timestamp> /opt/data/config.yaml
hermes gateway restart
```

Image rollback: change the compose tag back to `ghcr.io/keivry/hermes-office:v0.23.3`
(or the previous digest) and `docker compose up -d`.

## 1. Image identity (before looking at behaviour)

1. `docker inspect <container> --format '{{.Config.Image}} {{.Image}}'` and compare `.Image`
   with `docker image inspect ghcr.io/keivry/hermes-office:v0.23.4 --format '{{index .RepoDigests 0}}'`.
   A `pull` alone does not replace a running container — the container must be recreated.
2. In the container: `hermes --version` must print `v0.23.4`.
3. Check the patch layer really contains the patches (not just "the RUN command succeeded"):
   the expected patch surface is **22 files modified + `cron/scheduler_mcp.py` (new)**.
   Spot checks:

   ```bash
   grep -n 'node-compile-cache' /opt/hermes/agent/checkpoints/manager.py
   grep -n '_repair_bare_repo_dirs' /opt/hermes/agent/checkpoints/manager.py
   grep -n 'require_reasoning_text_echo' /opt/hermes/agent/codex_responses_adapter.py
   grep -n '_ReplayItem.from_stored({}' /opt/hermes/agent/codex_responses_adapter.py
   grep -n '^import asyncio' /opt/hermes/gateway/outbound/senders.py
   grep -n '_matrix_bridge_to_adapter_loop' /opt/hermes/gateway/outbound/senders.py
   ```

   All six must hit. No path moved in this bump, so a miss means the patch layer is wrong,
   not that the module was relocated.

## 2. Config migration

```bash
hermes config migrate
```

Expected: `_config_version: 54` and **no migration step runs**. v0.23.4 adds two defaults
without a schema step — `skills.index_desc_limit: 60` and `tui.program_status: true` — so a
config already at 54 simply gains nothing until the keys are read with their defaults. Also
confirm:

- `skills.write_approval_scope` still reads back as `create` (patch 039);
- `webapp` absent or `enabled: false`;
- `mcp_servers.chrome-devtools` still points at the volume binary and the volume Chromium path.

## 3. Volume-bound Python venvs (most common silent breakage)

The base keeps the same `python-3.14.9+20261021` build directory, so absolute links in volume
venvs stay valid. Check anyway:

```bash
for f in /opt/data/state/*/venv/pyvenv.cfg; do grep -q '/opt/hermes/tools' "$f" && echo "AT RISK: $f"; done
```

Any hit: rebuild that venv with a Python installed **on the data volume** (`uv python install 3.13`
under `/opt/data`), not with the image interpreter. Symptom cluster: plugin slash commands become
`Unrecognized`, reaction hooks go silent, cron scripts report `Script Error`.

This sweep already upgraded every volume venv to zero outdated packages (`.venv`,
`skill-audit`, `dingtalk-org`, `matrix-send`, `miniflux`, `pdf-translate`, `pdf2zh/uvenv`,
`todo`, `store/dingtalk-oa`); `pdf2zh/venv312` stays pinned to upstream-supported versions.

## 4. Plugins (volume-installed)

```bash
hermes plugins list
```

- All six must load: `clawmem`, `disk-cleanup`, `hermes-lcm`, `rtk-rewrite`, `security-guidance`, `todo`.
- v0.23.4 adds `hermes plugins config` and more catalog entries; no bundled plugin entrypoint
  was renamed.

## 5. MCP servers and the browser stack

```bash
ls -l /opt/data/home/.local/bin/chrome-devtools-mcp
/opt/data/home/.local/share/chromium/chrome/linux-158.0.8127.88/chrome --version
```

- `chrome-devtools-mcp` stays at 1.13.0 (npm latest).
- The volume Chromium was updated 158.0.8127.36 → **158.0.8127.88** (CfT stable patch) and
  `config.yaml` now pins
  `--executablePath=/opt/data/home/.local/share/chromium/chrome/linux-158.0.8127.88/chrome`.
  The old `linux-158.0.8127.36/` directory is intentionally kept for rollback; the running
  gateway keeps its old child until the next reconnect, the new path is used on restart.
- Patches 040/041 (cron MCP recovery/revive) are unchanged. Check the first scheduled tick
  after deploy for `MCP ... recovering` / `revived` lines and that the run has 29 MCP tools,
  not zero.

## 6. Matrix / gateway

- Patch 007: cron standalone Matrix delivery on a fresh loop must not log
  `Timeout context manager should be used inside a task`; verify a **cron-delivered Matrix
  message actually arrives**, not just that the log is clean.
- Patch 035: reaction events must still be forwarded to hooks (`set_reaction_handler`).
- Patch 036: a message whose text starts with `/` but looks like a path must NOT be treated as
  a command (`MessageType.COMMAND` stamping now comes from `get_command()`).
- Patch 011: restart exclusivity — only one restart owner; no double-restart during a drain.
  Its upstream PR #85285 is still **closed without merging**, so the patch is still required.
- E2EE: send one encrypted-room message from the gateway and one from a cron job; both must
  arrive with `BAD_ACCOUNT_KEY` absent from the log.

## 7. Agent behaviour that has patch-level fixes

- **Checkpoints** (015/016): trigger a file write and confirm `.hermes/checkpoints` gets a
  commit and `info/exclude` contains `node-compile-cache/`; then `rm -rf <store>/refs
  <store>/branches` and trigger another write — the store must self-heal instead of logging
  `fatal: not a git repository`.
- **Title generation** (014): a new session must not log
  `Title generation failed: 400 ... response_format`.
- **DeepSeek reasoning echo** (037/038): a multi-turn DeepSeek conversation with tool calls must
  not log `The reasoning_text ... must be passed back to the API`, including the orphan-turn
  case. The expected failure mode of a bad re-anchor would be
  `AttributeError: 'dict' object has no attribute 'position'` — no re-anchor was needed here.
- **Skills gate** (039): `create` writes should be auto-approved; `edit` / `delete` still require
  approval. Note that v0.23.4 wires `skills.index_desc_limit` through
  `_description_budget_error`; that change sits below the patched hunks and both features coexist.
- **File-read toolset** (008): `file_read` must appear in the quick-setup/toolset surface.

## 8. Cron jobs

- List every job and confirm `model` / provider still resolve (`custom:commandcode`).
- Run one job manually: deliver path, tool surface, and MCP registration are the three things
  that historically break across a base bump.
- Check `hermes cron` output for `Script Error` / missing interpreter, which points back to §3.

## 9. Post-deploy smoke (in the container)

```bash
hermes --version
hermes config show | head -40
hermes plugins list
hermes mcp list
python3 -c "import agent.checkpoints.manager, agent.codex_responses_adapter; import cron.scheduler_mcp; import gateway.outbound.senders; print('imports ok')"
```

Then send one Matrix DM, one cron delivery, and one skill-write, and confirm each in the log.

## 10. pnpm drift warning (roster 042)

042 is carried unchanged (pnpm is still 12.15.0 and still build-stage-only upstream; `class Pnpm`
still has no `optional` flag). After deploying an image that contains 042:

- `hermes status` / `hermes doctor` print **no** `install out of sync` line;
- `/opt/data/logs/gateway.log` gains no new occurrence after the restart;
- the check itself is still live:
  `/opt/hermes/.venv/bin/python -c 'import sys; sys.path.insert(0,"/opt/hermes"); import pm; print(pm.activate())'`
  → `[]`.

If the line is still there, confirm `grep -n "optional = True" /opt/hermes/pm/packages.py` hits
inside `class Pnpm` and that the build log shows
`==> Applying 042-pm-pnpm-build-only.patch`.

## 11. Component-pin spot checks

```bash
officecli --version    # 1.0.163
docling --version      # 2.152.0
gh --version           # 2.105.0
pdfcpu version         # 0.16.4
bun --version          # 1.4.5
clawmem --version      # 0.43.8
rtk --version          # 1.1.0  (v1.2.x musl SIGILLs on this host: no AVX)
sqlite3 --version      # 3.53.4 (3530400)
```

## 12. What did NOT change (don't chase it)

- Patch 018 (OpenCode custom-provider affinity) is still a no-op against the live
  `opencode.ai` base_url and still earns its keep only for an off-host relay.
- The cited upstream PRs did not move: #77100, #85285, #85713, #138896 and #99680 remain
  closed-not-merged; #133799, #146765 and #109061 remain open. Nothing is superseded by
  another commit in this window.
- `rtk` stays at v1.1.0: the v1.2.x x86_64 musl build still SIGILLs on this no-AVX host and
  upstream publishes no gnu asset for x86_64.
- `ppt-master` (v6.10.0), `pdfcpu` (0.16.4), `bun` (1.4.5), `gh` (v2.105.0) and the sqlite CLI
  pin (3530400) are already latest/coupled and were not bumped.
