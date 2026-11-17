# hermes-office v0.23.1 → v0.23.2 upgrade checklist

Written 2026-11-17, together with the v0.23.2 sweep. Test evidence lives in the Dockerfile
header ("2026-11-17 sweep") and in this repo's git history; this file is the **post-upgrade
check order** — run it top to bottom after the new image is deployed.

- Upstream base: `nousresearch/hermes-agent:v0.23.2`
  (index digest `sha256:d6746a084e9341baada483e3d6210444d3c1aeb7c130f0915150065fb2851459`)
- Patch roster: 16 (`007, 008, 011, 014, 015, 016, 018, 032, 035, 036, 037, 038, 039, 040, 041, 042`)
- ClawMem patch roster: 6 (`036, 040, 041, 042, 043, 044`), verified against clawmem 0.43.6
- Config schema: 53 (unchanged — v0.23.2 adds no migration step)
- Base runtime: python 3.14.9, node 26.12.1, npm **12.2.2** (was 12.0.2), uv 0.13.5, pnpm 12.15.0

## 0. Before touching the live container

```bash
cp -a /opt/data/config.yaml /opt/data/config.yaml.bak-$(date +%Y%m%dT%H%M%SZ)
```

Rollback (config only):

```bash
cp -a /opt/data/config.yaml.bak-<timestamp> /opt/data/config.yaml
hermes gateway restart
```

Image rollback: change the compose tag back to `ghcr.io/keivry/hermes-office:v0.23.1` and
`docker compose up -d`.

## 1. Image identity (before looking at behaviour)

1. `docker inspect <container> --format '{{.Config.Image}} {{.Image}}'` and compare `.Image`
   with `docker image inspect ghcr.io/keivry/hermes-office:v0.23.2 --format '{{index .RepoDigests 0}}'`.
   A `pull` alone does not replace a running container — the container must be recreated.
2. In the container: `hermes --version` must print `v0.23.2`.
3. Check the patch layer really contains the patches (not just "the RUN command succeeded"):
   the expected patch surface is **22 files modified + `cron/scheduler_mcp.py` (new)**, and
   since v0.23.2 patch 007 lands in `gateway/outbound/senders.py` (the old
   `tools/send_message_senders.py` no longer exists). Two spot checks:

   ```bash
   grep -n '^import asyncio' /opt/hermes/gateway/outbound/senders.py
   grep -n '_matrix_bridge_to_adapter_loop' /opt/hermes/gateway/outbound/senders.py
   ```

   Both must hit. The first one is load-bearing: the v0.23.1 form of patch 007 was dead code
   because `senders.py` did not import asyncio and the NameError was swallowed by the guard's
   own `try/except`.

## 2. Config migration

```bash
hermes config migrate
```

Expected: **no schema bump** (stays at `_config_version: 53`) and no changes beyond any
dead-key cleanup. If `agent.clarify_timeout` is 3600 it may be rewritten to 90 by the
existing v53 step; `skills.write_approval_scope` must still read back as `create` (patch 039),
and `webapp` must stay absent or `enabled: false`.

## 3. Volume-bound Python venvs (most common silent breakage)

The base renames `/opt/hermes/tools/python-3.14.9+<build>-*` on every patch release; volume venvs
keep absolute links into the old directory and then fail with `venv/bin/python: No such file`.
The python build in v0.23.2 is the same 20261021 build as v0.23.1, so this bump should not
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
- npm moved 12.0.2 → 12.2.2 in the base; the ClawMem global install uses
  `--prefix /usr/local --allow-scripts=node-llama-cpp`, which is unchanged in 12.2.x, but a
  build failure at that layer is the first place to look if the image build breaks.

## 5. MCP servers

```bash
ls -l /opt/data/home/.local/bin/chrome-devtools-mcp
ls -l /opt/data/home/.local/share/chromium/chrome/linux-*/chrome
```

- The base's bundled Chromium jumped 145 → 156 in this release, but this deployment pins
  `--executablePath=/opt/data/home/.local/share/chromium/chrome/linux-152.0.7977.42/chrome`
  on the volume. The base bump does not move it; a volume Chromium upgrade would. If the
  directory name changed, update the config value.
- Patches 040/041 (cron MCP recovery/revive) are unchanged by this bump. Check the first
  scheduled tick after deploy for `MCP ... recovering` / `revived` lines and that the run has
  29 MCP tools, not zero.

## 6. Matrix / gateway

- Patch 007 (re-anchored): cron standalone Matrix delivery on a fresh loop must not log
  `Timeout context manager should be used inside a task`; the send is scheduled onto the
  adapter's own loop. This is the patch whose asyncio import was missing before — verify a
  **cron-delivered Matrix message actually arrives**, not just that the log is clean.
- Patch 035: reaction events must still be forwarded to hooks (`set_reaction_handler`).
- Patch 036: a message whose text starts with `/` but looks like a path must NOT be treated as
  a command.
- Patch 011: restart exclusivity — only one restart owner; check for `active_turn_owner_alive`
  behaviour and no double-restart during a drain. Its upstream PR #85285 was closed
  **without merging**, so the patch is still required.
- E2EE: send one encrypted-room message from the gateway and one from a cron job; both must
  arrive with `BAD_ACCOUNT_KEY` absent from the log.

## 7. Agent behaviour that has patch-level fixes

- **Title generation** (014): a new session must not log
  `Title generation failed: 400 ... response_format`.
- **DeepSeek reasoning echo** (037/038): a multi-turn DeepSeek conversation with tool calls must
  not log `The reasoning_text ... must be passed back to the API`, including the orphan-turn case.
- **Checkpoints** (015/016): trigger a file write and confirm `.hermes/checkpoints` gets a commit;
  then `rm -rf <store>/refs <store>/branches` and trigger another write — the store must self-heal
  instead of logging `fatal: not a git repository`.
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
python3 -c "import tools.checkpoint_manager, toolsets, cron.scheduler_mcp; import gateway.outbound.senders; print('imports ok')"
```

Then send one Matrix DM, one cron delivery, and one skill-write, and confirm each in the log.

## 10. pnpm drift warning (roster 042)

042 is carried unchanged (pnpm is still 12.15.0 and still build-stage-only upstream). After
deploying an image that contains 042:

- `hermes status` / `hermes doctor` print **no** `install out of sync` line;
- `/opt/data/logs/gateway.log` gains no new occurrence after the restart;
- the check itself is still live:
  `/opt/hermes/.venv/bin/python -c 'import sys; sys.path.insert(0,"/opt/hermes"); import pm; print(pm.activate())'`
  → `[]`.

If the line is still there, the patch layer is stale — confirm
`grep -n "optional = True" /opt/hermes/pm/packages.py` hits inside `class Pnpm`
(line ~800) and that the build log shows `==> Applying 042-pm-pnpm-build-only.patch`.

## 11. Component-pin spot checks

```bash
officecli --version    # 1.0.162
docling --version      # 2.150.1
gh --version           # 2.104.0
pdfcpu version         # 0.16.4
bun --version          # 1.4.4
clawmem --version      # 0.43.6
rtk --version          # 1.1.0  (v1.2.0 SIGILLs on this host: no AVX)
sqlite3 --version      # 3.53.4 (3530400)
```
