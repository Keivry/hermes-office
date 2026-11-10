# hermes-office v0.22.7 → v0.23.1 upgrade checklist

Written 2026-11-10, together with the v0.23.1 sweep. Test evidence lives in the Dockerfile
header ("2026-11-10 sweep") and in this repo's git history; this file is the **post-upgrade
check order** — run it top to bottom after the new image is deployed.

- Upstream base: `nousresearch/hermes-agent:v0.23.1`
  (index digest `sha256:276d44685c65c0cb2a25f190b63c65c8906f9dc76486fb1c05ae71b5826bda08`)
- Patch roster: 15 (`007, 008, 011, 014, 015, 016, 018, 032, 035, 036, 037, 038, 039, 040, 041`)
- ClawMem patch roster: 6 (`036, 040, 041, 042, 043, 044`), verified against clawmem 0.43.6
- Config schema: 52 → 53

## 0. Before touching the live container

```bash
cp -a /opt/data/config.yaml /opt/data/config.yaml.bak-$(date +%Y%m%dT%H%M%SZ)
```

Rollback (config only):

```bash
cp -a /opt/data/config.yaml.bak-<timestamp> /opt/data/config.yaml
hermes gateway restart
```

Image rollback: change the compose tag back to `ghcr.io/keivry/hermes-office:v0.22.7` and
`docker compose up -d`.

## 1. Image identity (before looking at behaviour)

1. `docker inspect <container> --format '{{.Config.Image}} {{.Image}}'` and compare `.Image`
   with `docker image inspect ghcr.io/keivry/hermes-office:v0.23.1 --format '{{index .RepoDigests 0}}'`.
   A `pull` alone does not replace a running container — the container must be recreated.
2. In the container: `hermes --version` must print `v0.23.1`.
3. Check the patch layer really contains the patches (not just "the RUN command succeeded"):
   pull the small (<700 KB) layer from the registry manifest, untar it, and compare the 22
   touched files byte-for-byte with the locally applied tree. Expected files: 21 modified +
   `cron/scheduler_mcp.py` (new). The layer also contains `tmp/.wh.hermes-patches`.

## 2. Config migration

```bash
hermes config migrate
git -C /opt/data diff --no-index /path/to/config.yaml.bak-<ts> /opt/data/config.yaml | head -40
```

Expected: `Config version: 52 → 53`, and the **only** changed line is `_config_version: 52` → `53`.

- `agent.clarify_timeout` must stay `600` (migration 53 only rewrites the old default `3600`;
  the new default is 90).
- `skills.write_approval_scope` must still read back as `create` (patch 039). If it disappeared,
  every skill write is gated by `skills.write_approval` instead of only `create`.
- `webapp` must stay absent or `enabled: false` (v0.23.x serves nothing to browsers by default).

Optional cleanup (no functional effect, only removes dead keys):
`auxiliary.skills_hub`, `browser.record_sessions`.

## 3. Volume-bound Python venvs (most common silent breakage)

The base renames `/opt/hermes/tools/python-3.14.9+<build>-*` on every patch release; volume venvs
keep absolute links into the old directory and then fail with `venv/bin/python: No such file`.

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
- v0.23.x adds plugin API surface (session-scoped env, JSON-RPC methods/events, `llm.oneshot`,
  stable `conversation_id`, `on_session_open` / `post_curator_run` hooks). It is additive, but a
  plugin that imports a moved core module will fail at load — check the gateway log for the
  plugin names above, not just the process being up.
- The plugin-catalog fix (2 MiB → 16 MiB, #151860) means `hermes plugins install` now uses the
  live catalog. Only relevant if you install `camofox` or `advanced-delegation`; install them
  **after** the upgrade, not before.

## 5. MCP servers

```bash
ls -l /opt/data/home/.local/bin/chrome-devtools-mcp
ls -l /opt/data/home/.local/share/chromium/chrome/linux-*/chrome
```

- `config.yaml` pins `--executablePath=/opt/data/home/.local/share/chromium/chrome/linux-152.0.7977.42/chrome`.
  These live on the volume, so the base bump does not move them; a Chromium upgrade would. If the
  directory name changed, update the config value.
- `hermes mcp serve` was renamed **`hermes mcp-serve`** (moved into a plugin). This deployment does
  not invoke it (the entry is `chrome-devtools`), but any external script that starts Hermes as an
  MCP server must be updated — there is no automatic rewrite.
- Patches 040/041 (cron MCP recovery/revive) are the reason cron keeps `mcp__chrome_devtools__*`
  tools after an idle recycle. Check the first scheduled tick after deploy for
  `MCP ... recovering` / `revived` lines and that the run has 29 MCP tools, not zero.

## 6. Matrix / gateway

- Patch 007: cron standalone delivery on a fresh loop must not log
  `Timeout context manager should be used inside a task`; it should bridge onto the adapter loop.
- Patch 035: reaction events must still be forwarded to hooks (`set_reaction_handler`).
- Patch 036: a message whose text starts with `/` but looks like a path must NOT be treated as a
  command.
- Patch 011: restart exclusivity — only one restart owner; check for `active_turn_owner_alive`
  behaviour and no double-restart during a drain.
- E2EE: send one encrypted-room message from the gateway and one from a cron job; both must
  arrive with `BAD_ACCOUNT_KEY` absent from the log.

## 7. Agent behaviour that has patch-level fixes

- **Title generation** (014): a new session must not log
  `Title generation failed: 400 ... response_format`. The patch stops sending
  `response_format` to non-OpenAI providers.
- **DeepSeek reasoning echo** (037/038): a multi-turn DeepSeek conversation with tool calls must
  not log `The reasoning_text ... must be passed back to the API`, including the orphan-turn case
  where the sidecar was never persisted.
- **Checkpoints** (015/016): trigger a file write and confirm `.hermes/checkpoints` gets a commit;
  then `rm -rf <store>/refs <store>/branches` and trigger another write — the store must self-heal
  instead of logging `fatal: not a git repository`.
- **Skills gate** (039): `create` writes should be auto-approved; `edit` / `delete` still require
  approval.

## 8. Skills / docs cleanup (volume, not image)

These were already stale before v0.23.1 and are not caused by it, but check them once:

- `grep -rn 'browser_navigate\|browser_click\|browser_screenshot\|browser_snapshot' /opt/data/skills`
  — v0.22.7 already ships only `browser_exec`; every hit is a dead instruction.
- `hermes mcp serve` in `autonomous-ai-agents/hermes-agent/SKILL.md` → `hermes mcp-serve`.
- Upstream merged Word/PowerPoint/Excel skills into `microsoft-office`; the image's own
  `skills/productivity/{officecli,presentation-tools,document-extraction,...}` are copied over
  `/opt/hermes/skills` and are unaffected, but a volume copy of the old split skills will keep
  triggering alongside the umbrella one.

## 9. Cron jobs

- List every job and confirm `model` / provider still resolve (`custom:commandcode`).
- Run one job manually: deliver path, tool surface, and MCP registration are the three things that
  historically break across a base bump.
- Check `hermes cron` output for `Script Error` / missing interpreter, which points back to §3.

## 10. Post-deploy smoke (in the container)

```bash
hermes --version
hermes config show | head -40
hermes plugins list
hermes mcp list
python3 -c "import tools.checkpoint_manager, toolsets, cron.scheduler_mcp; print('imports ok')"
```

Then send one Matrix DM, one cron delivery, and one skill-write, and confirm each in the log.

## 11. pnpm drift warning (roster 042)

Before 042 every `hermes ...` dispatch printed
`install out of sync (pnpm: not installed or outdated) — this docker-managed
install must rebuild the artifact to fix`, and the gateway logged the same line
once per boot. It is a false positive: v0.23.1 installs pnpm in the build stages
only, while `class Pnpm` had no `optional` flag. 042 marks it optional.

After deploying an image that contains 042:

- `hermes status` / `hermes doctor` print **no** `install out of sync` line;
- `/opt/data/logs/gateway.log` gains no new occurrence after the restart;
- the check itself is still live:
  `/opt/hermes/.venv/bin/python -c 'import sys; sys.path.insert(0,"/opt/hermes"); import pm; print(pm.activate())'`
  → `[]`.

If the line is still there, the patch layer is stale — confirm
`grep -n "optional = True" /opt/hermes/pm/packages.py` hits inside `class Pnpm`
(line ~800) and that the build log shows `==> Applying 042-pm-pnpm-build-only.patch`.
