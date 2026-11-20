# hermes-office v0.23.2 → v0.23.3 upgrade checklist

Written 2026-11-20, together with the v0.23.3 sweep. Test evidence lives in the Dockerfile
header ("2026-11-20 sweep") and in this repo's git history; this file is the **post-upgrade
check order** — run it top to bottom after the new image is deployed.

- Upstream base: `nousresearch/hermes-agent:v0.23.3`
  (index digest `sha256:3e9fe4c6ef36490f43aa0d0d80f9df64e9c92a576eee3042f1a97c8813c05355`)
- Patch roster: 16 (`007, 008, 011, 014, 015, 016, 018, 032, 035, 036, 037, 038, 039, 040, 041, 042`)
  — **zero retired, four re-anchored** (015, 016, 037, 038)
- ClawMem patch roster: 6 (`036, 040, 041, 042, 043, 044`), verified against clawmem 0.43.6
- Config schema: **54** (was 53; v53→54 only adds `prompt_caching.cache_ttl: auto` semantics)
- Base runtime: python 3.14.9 (build 20261021), node 26.12.1, npm 12.2.2, uv 0.13.5, pnpm 12.15.0
  — identical to v0.23.2. The base Dockerfile is byte-identical; the only `pm/lock.json` change
  is cua-driver 0.21.0 → 0.52.0 (unused here).

## 0. Before touching the live container

```bash
cp -a /opt/data/config.yaml /opt/data/config.yaml.bak-$(date +%Y%m%dT%H%M%SZ)
```

Rollback (config only):

```bash
cp -a /opt/data/config.yaml.bak-<timestamp> /opt/data/config.yaml
hermes gateway restart
```

Image rollback: change the compose tag back to `ghcr.io/keivry/hermes-office:v0.23.2`
(or the previous digest) and `docker compose up -d`.

## 1. Image identity (before looking at behaviour)

1. `docker inspect <container> --format '{{.Config.Image}} {{.Image}}'` and compare `.Image`
   with `docker image inspect ghcr.io/keivry/hermes-office:v0.23.3 --format '{{index .RepoDigests 0}}'`.
   A `pull` alone does not replace a running container — the container must be recreated.
2. In the container: `hermes --version` must print `v0.23.3`.
3. Check the patch layer really contains the patches (not just "the RUN command succeeded"):
   the expected patch surface is **22 files modified + `cron/scheduler_mcp.py` (new)**.
   Spot checks for the four re-anchors:

   ```bash
   grep -n 'node-compile-cache' /opt/hermes/agent/checkpoints/manager.py
   grep -n '_repair_bare_repo_dirs' /opt/hermes/agent/checkpoints/manager.py
   grep -n 'require_reasoning_text_echo' /opt/hermes/agent/codex_responses_adapter.py
   grep -n '_ReplayItem.from_stored({}' /opt/hermes/agent/codex_responses_adapter.py
   grep -n '^import asyncio' /opt/hermes/gateway/outbound/senders.py
   grep -n '_matrix_bridge_to_adapter_loop' /opt/hermes/gateway/outbound/senders.py
   ```

   All six must hit. `tools/checkpoint_manager.py` no longer exists in v0.23.3 — the checkpoint
   manager is `agent/checkpoints/manager.py`.

## 2. Config migration

```bash
hermes config migrate
```

Expected: `_config_version: 54`. The only schema step is v53→54: a template-seeded
`prompt_caching.cache_ttl: "5m"` is removed so the new default `auto` applies (1h for
human-paced sessions, 5m for machine-paced). A user-pinned `5m` is kept and a notice printed;
either outcome is fine. Also confirm:

- `skills.write_approval_scope` still reads back as `create` (patch 039);
- `webapp` absent or `enabled: false`;
- `agent.clarify_timeout` stays at whatever v53 left it (90 unless user-pinned).

The new prompt-cache lifecycle controller is on by default in this window. If the deployment
must keep the old 5m-only behaviour, pin `prompt_caching.cache_ttl: "5m"` explicitly **before**
running the migration (otherwise it is treated as template-seeded and dropped).

## 3. Volume-bound Python venvs (most common silent breakage)

The base renames `/opt/hermes/tools/python-3.14.9+<build>-*` on a patch release; volume venvs
keep absolute links into the old directory and then fail with `venv/bin/python: No such file`.
The python build in v0.23.3 is the same 20261021 build as v0.23.2, so this bump should not
break them — check anyway:

```bash
for f in /opt/data/state/*/venv/pyvenv.cfg; do grep -q '/opt/hermes/tools' "$f" && echo "AT RISK: $f"; done
```

Any hit: rebuild that venv with a Python installed **on the data volume** (`uv python install 3.13`
under `/opt/data`), not with the image interpreter. Symptom cluster: plugin slash commands become
`Unrecognized`, reaction hooks go silent, cron scripts report `Script Error`.

## 4. Plugins (volume-installed)

```bash
hermes plugins list
```

- All six must load: `clawmem`, `disk-cleanup`, `hermes-lcm`, `rtk-rewrite`, `security-guidance`, `todo`.
- v0.23.3 expands the plugin API/catalog but does not rename the bundled plugin entrypoints.

## 5. MCP servers

```bash
ls -l /opt/data/home/.local/bin/chrome-devtools-mcp
ls -l /opt/data/home/.local/share/chromium/chrome/linux-*/chrome
```

- The bundled Chromium is unchanged at 156; this deployment still pins
  `--executablePath=/opt/data/home/.local/share/chromium/chrome/linux-152.0.7977.42/chrome`
  on the volume. If the directory name changed, update the config value.
- Patches 040/041 (cron MCP recovery/revive) are unchanged by this bump. Check the first
  scheduled tick after deploy for `MCP ... recovering` / `revived` lines and that the run has
  29 MCP tools, not zero.

## 6. Matrix / gateway

- Patch 007: cron standalone Matrix delivery on a fresh loop must not log
  `Timeout context manager should be used inside a task`; verify a **cron-delivered Matrix
  message actually arrives**, not just that the log is clean.
- Patch 035: reaction events must still be forwarded to hooks (`set_reaction_handler`).
- Patch 036: a message whose text starts with `/` but looks like a path must NOT be treated as
  a command (`MessageType.COMMAND` stamping now comes from `get_command()`).
- Patch 011: restart exclusivity — only one restart owner; check `active_turn_owner_alive`
  behaviour and no double-restart during a drain. Its upstream PR #85285 is still
  **closed without merging**, so the patch is still required.
- E2EE: send one encrypted-room message from the gateway and one from a cron job; both must
  arrive with `BAD_ACCOUNT_KEY` absent from the log.

## 7. Agent behaviour that has patch-level fixes

- **Checkpoints** (015/016, new module): trigger a file write and confirm
  `.hermes/checkpoints` gets a commit and `info/exclude` contains `node-compile-cache/`; then
  `rm -rf <store>/refs <store>/branches` and trigger another write — the store must self-heal
  instead of logging `fatal: not a git repository`.
- **Title generation** (014): a new session must not log
  `Title generation failed: 400 ... response_format`.
- **DeepSeek reasoning echo** (037/038): a multi-turn DeepSeek conversation with tool calls must
  not log `The reasoning_text ... must be passed back to the API`, including the orphan-turn
  case. This release changed the replay item type to `_ReplayItem`; a wrong re-anchor would
  surface as `AttributeError: 'dict' object has no attribute 'position'`, not as the old 400.
- **Skills gate** (039): `create` writes should be auto-approved; `edit` / `delete` still require
  approval.

## 8. Cron jobs

- List every job and confirm `model` / provider still resolve (`custom:commandcode`).
- Run one job manually: deliver path, tool surface, and MCP registration are the three things that
  historically break across a base bump.
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
officecli --version    # 1.0.162
docling --version      # 2.151.1
gh --version           # 2.105.0
pdfcpu version         # 0.16.4
bun --version          # 1.4.5
clawmem --version      # 0.43.6
rtk --version          # 1.1.0  (v1.2.x musl SIGILLs on this host: no AVX)
sqlite3 --version      # 3.53.4 (3530400)
```

## 12. What did NOT change (don't chase it)

- Patch 018 (OpenCode custom-provider affinity) is still a no-op against the live
  `opencode.ai` base_url and still earns its keep only for an off-host relay.
- 008/011/032/035/036/039/040/041/042 were not touched by v0.23.3; their upstream issues/PRs
  are still open or closed-unmerged (see the Dockerfile sweep note).
- ClawMem 0.43.6 remains npm-latest; no patch re-anchor was needed.
