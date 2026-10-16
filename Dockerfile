# Base tag: v0.22.2 is the release v0.22.1 was meant to be -- 0.22.1 was built from the wrong
# commit and shipped unreleased gateway work. Both publish a REAL bare Docker tag.
# `nousresearch/hermes-agent:v0.22.2` multi-arch index digest
# sha256:36099926da316742423544e055d4734777105ffe6341873af5459b957d0c2919 (read back from
# the registry), so this pin and the promoted release image cannot drift apart.
#
# The tag is annotated (object 7b77e29e) and its own message records the release it was cut
# from: claimTag rc.2-v0.22.2, commit d923a5eb, dockerManifestDigest sha256:36099926... --
# the same digest as the index above, which is the cheapest way to re-verify a bump.
#
# Base runtime, read from pm/lock.json of the tagged tree: python 3.14.7, node v26.7.0,
# npm 12.0.2, uv 0.12.3 -- identical to v0.22.1, so no npm/pip/uv flag in this Dockerfile
# needed re-checking for the bump. The base Dockerfile is byte-identical between v0.22.1 and
# v0.22.2 (543 lines, zero diff), and SQLITE_AUTOCONF_VERSION is still 3530400 in both, so the
# sqlite CLI pin below is untouched. The 300-file v0.22.1->v0.22.2 delta is all under the
# base image's own paths (gateway boot epoch, local-model streaming, profiles, Windows
# packaging, catalog) plus release plumbing.
#
# Known upstream issue carried by this base: "Sessions that ran under the 0.22.1 gateway
# can't be deleted in 0.22.2" (release notes). This deployment ran v0.22.1 from 2026-10-14, so
# pre-existing sessions in state.db may fail to delete until upstream addresses it.

ARG HERMES_AGENT_VERSION=v0.22.2
ARG HERMES_OFFICE_VERSION=${HERMES_AGENT_VERSION}
FROM nousresearch/hermes-agent:${HERMES_AGENT_VERSION}

ARG DEBIAN_FRONTEND=noninteractive
ARG OFFICECLI_VERSION=v1.0.157
ARG OFFICECLI_ASSET=officecli-linux-x64
ARG OFFICECLI_REPO=iOfficeAI/OfficeCli
ARG PPT_MASTER_VERSION=v6.7.0
ARG PPT_MASTER_ARCHIVE_URL=https://github.com/hugohe3/ppt-master/archive/refs/tags/${PPT_MASTER_VERSION}.tar.gz
ARG DOCLING_VERSION=2.139.0
ARG TORCH_CPU_WHL=https://download.pytorch.org/whl/cpu/torch-2.14.1%2Bcpu-cp313-cp313-manylinux_2_28_x86_64.whl#sha256=331fa474e26e428e2e6af1143b2fdab19cee492d7d21897b8899ce1c14755662
ARG TORCHVISION_CPU_WHL=https://download.pytorch.org/whl/cpu/torchvision-0.29.1%2Bcpu-cp313-cp313-manylinux_2_28_x86_64.whl#sha256=7b27accfa545169ad070efb8a6679b25d63acc8513bbc0c05937c3ce94c13ea5
ARG PDFCPU_VERSION=0.16.2
ARG PDFCPU_ASSET_URL=https://github.com/pdfcpu/pdfcpu/releases/download/v${PDFCPU_VERSION}/pdfcpu_${PDFCPU_VERSION}_Linux_x86_64.tar.xz
ARG BUN_VERSION=1.4.3
ARG BUN_ASSET_NAME=bun-linux-x64-baseline.zip
ARG BUN_ASSET_URL=https://github.com/oven-sh/bun/releases/download/bun-v${BUN_VERSION}/${BUN_ASSET_NAME}
ARG BUN_SHASUMS_URL=https://github.com/oven-sh/bun/releases/download/bun-v${BUN_VERSION}/SHASUMS256.txt
ARG CLAWMEM_VERSION=0.43.3
# RTK ships two editions from the same tag: `rtk-<target>` (Apache-2.0 CLI linking the
# BUSL-1.1 `rtk-engine`) and `rtk-oss-<target>` (Apache-2.0 only). This image takes the
# oss edition: v1.0.0 split the compression engine out under BUSL-1.1 (source-available,
# Change Date 2030-09-09 -> Apache-2.0), and the oss edition is byte-for-byte equivalent
# for everything this deployment uses -- rtk-hermes only ever calls `rtk rewrite`, and the
# `rewrite` verdict + all command filters + `rtk gain` live in the Apache half. Verified on
# the v1.0.1 bump: 6/6 rewrite verdicts and the `ls`/`git` compressed output are identical
# between editions, and `rtk rewrite` still returns the rc=3 that rtk-hermes accepts
# (_RTK_REWRITE_OK_CODES = {0, 3}). Nothing here uses the engine-only pipeline/plugin
# surface, and nothing referenced the removed `--ultra-compact` flag.
ARG RTK_VERSION=v1.0.1
ARG RTK_ASSET=rtk-oss-x86_64-unknown-linux-musl.tar.gz
ARG RTK_ASSET_SHA256=a44e8ffc43981100b4ddf1710399a1649a6c874591aa6d0c0727fe6cbd983c41
ARG GH_VERSION=v2.102.0
ARG GH_ASSET=gh_2.102.0_linux_amd64.tar.gz
ARG GH_ASSET_URL=https://github.com/cli/cli/releases/download/${GH_VERSION}/${GH_ASSET}
# Official sqlite3 CLI matching the base image's bundled libsqlite3 3.53.4 in
# /usr/local/lib. Debian's /usr/bin/sqlite3 (compiled against 3.46.1) resolves
# /usr/local/lib first via ld.so.conf.d and refuses to run with "header and
# source version mismatch". Pin the matching tools zip under /usr/local/bin.
# DO NOT bump this with the base image. The pin is COUPLED to the libsqlite3 the base
# builds: v0.22.1 still sets `SQLITE_AUTOCONF_VERSION=3530400` upstream (re-checked in the
# tagged Dockerfile on this bump -- verified against the real v0.22.0 Dockerfile too: the ARG
# is 3530400 in both) and installs
# libsqlite3.so.3.53.4 into /usr/local/lib. A 3.54 CLI resolves that 3.53.4 runtime
# library first (ld.so.conf.d) and refuses to start -- the exact failure this pin
# exists to avoid. Latest-tools-zip (3540000) is deliberately NOT taken. Bump only
# when the base's SQLITE_AUTOCONF_VERSION moves, and with the new zip's SHA256.
ARG SQLITE_VERSION=3530400
ARG SQLITE_ASSET_URL=https://www.sqlite.org/2026/sqlite-tools-linux-x64-${SQLITE_VERSION}.zip
ARG SQLITE_ASSET_SHA256=7a6f4d1720e4bc13faa3d934bfce37b816a496c0a2480deacd64cfd8be6cf224

LABEL org.opencontainers.image.title="hermes-office"
LABEL org.opencontainers.image.description="Hermes Agent image bundled with OfficeCLI, PPT Master, ImageMagick, Docling, pdfcpu, qpdf, poppler-utils, Bun, ClawMem, RTK, and common CLI utilities (gh, jq, less, ...)"
LABEL org.opencontainers.image.source="https://github.com/Keivry/hermes-office"
LABEL org.opencontainers.image.vendor="Keivry"
LABEL org.opencontainers.image.licenses="Apache-2.0, MIT"

ARG HERMES_OFFICE_VERSION
ARG HERMES_AGENT_VERSION

LABEL org.opencontainers.image.version="${HERMES_OFFICE_VERSION}"

USER root

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    imagemagick \
    libcairo2-dev \
    libicu-dev \
    pandoc \
    patch \
    pkg-config \
    poppler-utils \
    qpdf \
    unzip \
    xz-utils \
    dnsutils \
    file \
    git-lfs \
    iproute2 \
    jq \
    less \
    lsof \
    mtr \
    net-tools \
    netcat-openbsd \
    rsync \
    sqlite3 \
    strace \
    traceroute \
    tree \
    wget \
    yq \
    zip \
    zstd \
    && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL -o /usr/local/bin/officecli \
    "https://github.com/${OFFICECLI_REPO}/releases/download/${OFFICECLI_VERSION}/${OFFICECLI_ASSET}" \
    && chmod +x /usr/local/bin/officecli \
    && officecli --version

RUN curl -fsSL "${PDFCPU_ASSET_URL}" -o /tmp/pdfcpu.tar.xz \
    && tar -xJf /tmp/pdfcpu.tar.xz -C /tmp \
    && install -m 0755 /tmp/pdfcpu_${PDFCPU_VERSION}_Linux_x86_64/pdfcpu /usr/local/bin/pdfcpu \
    && rm -rf /tmp/pdfcpu.tar.xz /tmp/pdfcpu_${PDFCPU_VERSION}_Linux_x86_64

RUN curl -fsSL "${GH_ASSET_URL}" -o /tmp/gh.tar.gz \
    && tar -xzf /tmp/gh.tar.gz -C /tmp \
    && install -m 0755 "/tmp/gh_${GH_VERSION#v}_linux_amd64/bin/gh" /usr/local/bin/gh \
    && rm -rf /tmp/gh.tar.gz "/tmp/gh_${GH_VERSION#v}_linux_amd64" \
    && gh --version

RUN curl -fsSL "${BUN_ASSET_URL}" -o "/tmp/${BUN_ASSET_NAME}" \
    && curl -fsSL "${BUN_SHASUMS_URL}" -o /tmp/SHASUMS256.txt \
    && grep "  ${BUN_ASSET_NAME}$" /tmp/SHASUMS256.txt > /tmp/bun.sha256 \
    && (cd /tmp && sha256sum -c bun.sha256) \
    && unzip -q "/tmp/${BUN_ASSET_NAME}" -d /tmp \
    && install -m 0755 /tmp/bun-linux-x64-baseline/bun /usr/local/bin/bun \
    && rm -rf "/tmp/${BUN_ASSET_NAME}" /tmp/SHASUMS256.txt /tmp/bun.sha256 /tmp/bun-linux-x64-baseline \
    && bun --version

RUN curl -fsSL "https://github.com/rtk-ai/rtk/releases/download/${RTK_VERSION}/${RTK_ASSET}" -o /tmp/rtk.tar.gz \
    && echo "${RTK_ASSET_SHA256}  /tmp/rtk.tar.gz" | sha256sum -c - \
    && tar -xzf /tmp/rtk.tar.gz -C /tmp \
    && install -m 0755 /tmp/rtk /usr/local/bin/rtk \
    && rm -rf /tmp/rtk.tar.gz /tmp/rtk \
    && rtk --version

# Replace the broken Debian sqlite3 CLI with the official 3.53.4 tools zip so
# the CLI version matches the /usr/local/lib libsqlite3 the base image ships.
RUN curl -fsSL "${SQLITE_ASSET_URL}" -o /tmp/sqlite-tools.zip \
    && echo "${SQLITE_ASSET_SHA256}  /tmp/sqlite-tools.zip" | sha256sum -c - \
    && unzip -q /tmp/sqlite-tools.zip -d /tmp/sqlite-tools \
    && install -m 0755 /tmp/sqlite-tools/sqlite3 /usr/local/bin/sqlite3 \
    && rm -rf /tmp/sqlite-tools.zip /tmp/sqlite-tools \
    && sqlite3 --version

# npm 12 (the base's pinned npm -- 12.0.2 in v0.21.6, v0.21.7, v0.22.0 AND v0.22.1, checked in
# pm/lock.json) removed --unsafe-perm and now hard-errors on
# unknown CLI flags (EUNKNOWNCONFIG) instead of ignoring them. It was never
# needed here anyway: npm >= 7 runs lifecycle scripts as root by default, and
# clawmem ships no install/postinstall script of its own.
#
# --prefix /usr/local pins the global tree exactly where this image's ENV and
# PATH expect it (/usr/local/bin/clawmem). The base resolves node
# through a symlink into its PM store (/opt/hermes/tools/node-*/bin/node), so
# npm's implicit global prefix follows that store -- a directory that is not on
# the image PATH -- and a bare `-g` install would drop the clawmem CLI where
# neither CLAWMEM_BIN nor PATH can reach it. Asserted below, so it cannot
# regress silently again.
#
# --allow-scripts re-enables the one dependency install script npm 12 blocks by
# default (npm 11, in the previous base, ran it): node-llama-cpp's postinstall
# resolves the llama.cpp native binaries ClawMem loads when local models are on.
RUN npm install -g --prefix /usr/local --no-fund --no-audit \
        --allow-scripts=node-llama-cpp "clawmem@${CLAWMEM_VERSION}" \
    && test -x /usr/local/bin/clawmem \
    && node -e 'const fs=require("fs"); const pkg=JSON.parse(fs.readFileSync("/usr/local/lib/node_modules/clawmem/package.json","utf8")); console.log(`clawmem ${pkg.version}`)'

RUN mkdir -p /opt/tools /opt/tools/clawmem-plugin \
    && CLAWMEM_NODE_ROOT=/usr/local/lib/node_modules \
    && curl -fsSL "${PPT_MASTER_ARCHIVE_URL}" -o /tmp/ppt-master.tar.gz \
    && tar -xzf /tmp/ppt-master.tar.gz -C /opt/tools \
    && mv "/opt/tools/ppt-master-${PPT_MASTER_VERSION#v}" /opt/tools/ppt-master \
    && cp -R "${CLAWMEM_NODE_ROOT}/clawmem/src/hermes/." /opt/tools/clawmem-plugin/ \
    && rm -f /tmp/ppt-master.tar.gz \
    && chown -R hermes:hermes /opt/tools

# Hermes venv was created during base image build as root;
# make it writable so rtk-hermes and future pip-installed plugins
# can be added under USER hermes.
RUN chown -R hermes:hermes /opt/hermes/.venv

# The base deliberately keeps uv off PATH: PM resolves the pinned uv
# (0.12.3, in its own store) and hands build consumers Python environments,
# not installer executables -- /usr/local/bin gets node, npm and python3 but
# never uv. This image assembles its own third-party tool venvs under
# /opt/tools, so re-expose that same pinned binary through the same mechanism
# the base uses (a /usr/local/bin symlink) for the build only.
#
# pm.uv_launcher() is PM's read-only accessor for that binary; the obvious
# installed_package("uv") refuses it ("uv is internal PM tooling, not an
# application package"). The last uv consumer below removes the shim again, so
# the published image keeps upstream's "no installer on PATH" shape.
RUN UV_BIN="$(python3 -c 'import sys; sys.path.insert(0, "/opt/hermes"); from pm import uv_launcher; print(uv_launcher("uv") or "")')" \
    && test -x "$UV_BIN" \
    && ln -sf "$UV_BIN" /usr/local/bin/uv \
    && uv --version

# Install rtk-hermes into Hermes venv as root (venv may be root-owned in v0.18.0 base)
RUN uv pip install --python /opt/hermes/.venv/bin/python --no-cache-dir \
    "rtk-hermes==1.2.3"

# ── Upstream hotfix patches ──────────────────────────────────────────────
# Apply pending upstream fixes from patches/ (unified diff, `patch -p1`).
# Each .patch is applied in lexicographic order against /opt/hermes; a failing
# patch aborts the build so a half-patched image never ships. Remove a patch
# file once the fix is merged upstream and HERMES_AGENT_VERSION is bumped.
#
# ClawMem is NOT in this roster: it is a global npm install outside /opt/hermes,
# so its patches live in patches/clawmem/ and are applied against the installed
# package root by the "ClawMem package patches" step further down. The glob
# here cannot match them.
#
# As of v0.22.1 (2026-10-14) the roster was 9 patches: 033 was RETIRED on that bump (see the
# v0.22.1 sweep block below -- upstream main's 357986e58 + 3d8dfc1da landed the same fix, and
# both are ancestors of the tag). The other nine re-applied at fuzz 0 with zero .rej/.orig and
# needed no re-anchoring; 016 reports a standalone FAIL only because it depends on 015, and
# applies clean in lexicographic order. (034 was retired earlier, on the v0.21.7 bump.)
# 036 was ADDED on 2026-10-15 WITHOUT a base bump (roster 9 -> 10) -- see its own block near the
# end of this header. Note the number is the NEXT ONE IN THIS ROSTER, independent of
# patches/clawmem/036: the two rosters are applied by different globs against different trees and
# have never shared a sequence.
# 037 was ADDED on 2026-10-16 WITH the v0.22.2 base bump (roster 10 -> 11) -- see its own block
# near the end of this header.
# 038 was ADDED on 2026-10-16 WITHOUT a base bump (roster 11 -> 12). It is a FOLLOW-UP to 037 on
# the same symptom and a DIFFERENT root cause: 037 pads reasoning_text onto replayed items that
# exist, while a turn whose reasoning sidecar was never persisted replays ZERO items and had
# nothing to pad. BOTH stay -- 037 treats the all-turns-have-sidecars session shape, 038 the
# orphan-turn shape. See its own block near the end of this header.
# `ls patches/*.patch | wc -l` is the truth, not this paragraph: it read 7 through the
# v2026.9.24 sweep while the disk held 9, and 10 while the disk held 11. Reconcile it
# against the disk every sweep before trusting any count here.
# 17 were retired at v2026.9.11 (v0.21.2):
# 009/010 (empty tool_calls dedup + wire boundary), 012 (gateway stderr
# timestamps) and 013 (update_cmd SyntaxWarning) went in earlier tags; the
# rest were retired on this bump after every one of their upstream merge
# commits was verified an ancestor of v2026.9.11 (gh api
# compare/v2026.9.11...<mergeCommit> == "behind"):
#   017 #101864 opencode-session-affinity | 019 #100972 FIFO overflow rescue |
#   020 #101968 muse-spark tool-use enforcement | 021 #101949 muse-spark 1M
#   context | 022 #101948 muse-spark 1.3 catalog | 023 #101499 /goal admin
#   gate | 024 #100909 Matrix password credential | 025 #101118 shutdown
#   quiesce | 026 #100746 provider-overflow recovery | 027 #101483 GitSpawn
#   RCE | 028 #100967 tool-loop guardrails | 029 #100979 tool-search
#   validation | 030 #100135 init fallback chain.
# NOTE: 020-022 were the Muse Spark vendors. They are dropped because upstream
# now carries them, NOT because this deployment stopped using muse-spark — the
# two reasons happen to coincide.
#
# 2026-09-22 sweep (v2026.9.21 / v0.21.4): roster 8 -> 7. This tag is a patch
# rollup of 1,812 PRs / 5,071 non-merge commits, so upstream drift was expected.
# Every patch was re-verified three ways against a pristine checkout of the tag:
# (a) a real `patch -p1 --dry-run` FORWARD and REVERSE per file, (b) every added
# line searched in the tagged source, (c) the upstream issue/PR state plus
# `gh api compare/v2026.9.21...<mergeCommit>` ancestry. No survivor's fix is
# upstream: #77100 is still CLOSED-not-merged and #44347 / #85207 / #85713 /
# #78888 / #65349 / #83036 are still OPEN, while each flagged bug is still
# present in the tagged source (no active_turn_pid / active_turn_owner_alive,
# no node-compile-cache exclude, _repair_bare_repo_dirs still called ONLY from
# _gc_store, no file_read toolset, no Matrix adapter-loop bridge,
# title_generator still sends response_format).
# 4 of 7 re-applied unchanged (offset-only); 011, 014 and 018 were re-anchored.
#
# All 7 were re-verified against v2026.9.21 by a real `patch -p1` apply in
# lexicographic order on a pristine checkout (rc=0, zero .rej/.orig, every
# touched file compiled), plus a functional check of 018's new signature.
#
# 2026-09-24 sweep (v2026.9.24 / v0.21.5): roster stays at 7. Patch rollup of 460
# PRs / 1,610 non-merge commits (curated notes deferred to v0.22.0) -- drift was
# checked, not assumed: (a) every patch real-applied to a pristine checkout in
# lexicographic order, (b) upstream issue/PR state plus merge-commit ancestry vs
# v2026.9.24, (c) each flagged bug still present in the tagged source.
# No survivor's fix is upstream: #77100 is still CLOSED-not-merged and #44347 /
# #85207 / #85285 / #85713 / #78888 / #65349 / #83036 are still OPEN.
# 007 STAYS despite its closing comment claiming the generic loop bridge covers the
#   same ground: that bridge lives in _send_via_adapter (slack/wecom + the plugin
#   fallback), while matrix dispatches through _CHUNKED_ROUTES ->
#   _send_matrix_via_adapter, and cron standalone delivery still runs the send under
#   asyncio.run() on a fresh thread loop (cron/scheduler_delivery.py) -- the loop
#   mismatch 007 bridges is therefore still reachable.
# 016 STAYS: its upstream triage comment names #65354 as the fix, but that PR is OPEN.
# 011 was RE-ANCHORED: upstream replaced the _now() argument at its mark_turn_active
#   call site with datetime.now(timezone.utc); the other 6 re-applied offset-only.
# Verified: 7 x `patch -p1` on a pristine v2026.9.24 tree -> rc=0, zero .rej/.orig,
# all 12 touched files py_compile clean, per-patch markers present, plus a functional
# check of 018 (custom:opencode -> True, commandcode -> False, x-opencode-session
# merged, oneshot- fallback intact, unrelated custom provider untouched).
#
# 2026-10-09 sweep (v0.21.6): roster 9 -> 8. This tag is the first patch rollup from
# upstream's new stable pipeline -- 2,106 merged PRs / 8,867 non-merge commits / 8,342
# changed files -- and the curated notes are deferred to v0.22.0, so drift was checked,
# not assumed: (a) every patch real-applied to a pristine checkout of the tag in
# lexicographic order, (b) upstream issue/PR state plus merge-commit ancestry vs
# v0.21.6, (c) each flagged bug still present in the tagged source, (d) a functional
# check per patch on the freshly applied tree.
# 031 RETIRED: upstream b46f182f8 "fix(skills): render per-op diffs for staged batch
#   skill writes" landed the same fix and goes further -- _batch_pending_diff() also
#   renders each op against what the previous op left staged, which 031 did not. The
#   PR 031 cited (#99722) is still OPEN, which is exactly why this sweep checks the
#   source and the ancestry instead of the issue state.
# 016 KEPT and REWRITTEN: the checkpoint refactor moved gc into
#   checkpoint_pruning.Pruner.reclaim(), which recreates refs/heads + branches -- but
#   only AFTER a `_git()` call that RAISES on failure. A failed or timed-out gc
#   (upstream documents gc being killed by the store timeout) therefore skips the
#   repair and leaves the store unusable forever: every later command, including the
#   next prune's gc, dies with `fatal: not a git repository`, so the repair can never
#   run again. The old _gc_store() called _repair_bare_repo_dirs() through a _run_git()
#   that never raised, so the refactor made this strictly more fragile. 016 re-adds
#   _repair_bare_repo_dirs() (upstream deleted it) and keeps both the proactive repair
#   and the retry-on-fatal. Mechanism verified, not copied: git needs HEAD + objects/ +
#   refs/ to treat a directory as a repository, removing refs/ reproduces the exact
#   fatal this deployment logged (errors.log.2, 2026-08-21), the repair's
#   mkdir(parents=True) on refs/heads also restores refs/, and _run_git recovers.
# 015 KEPT: DEFAULT_EXCLUDES still lacks node-compile-cache/ and info/exclude is still
#   written only at store init, so a pre-existing store never picks the pattern up.
#   Re-anchored onto v0.21.6's reformatted DEFAULT_EXCLUDES (comment-per-group) and the
#   reshaped _init_store.
# 011 KEPT: #85207/#85285 still OPEN. Upstream added its own active_turn_token /
#   active_turn_started_at pairing, but recover_interrupted_turns() promotes a FRESH
#   marker to resume_pending without ever asking whether the owning process is alive,
#   so the detached-restart double loop 011 closes is still reachable. Re-anchored onto
#   the new _set_turn_marker_locked signature (the old hunks needed fuzz 2).
# 032 KEPT: still a flat `len(out) > 3000` cap in gateway/slash_commands.py, and the
#   truncation note now lives in locales/*.yaml with the same wrong hard-coded
#   ~/.hermes/pending/skills/<id>.json path. Re-anchored to post-process that i18n note.
# 007/008/014/018 unchanged in substance: #77100 CLOSED-not-merged, #44347 OPEN,
#   #85713 OPEN, and 018 is office-specific -- re-checked against the tagged source.
#   All four re-applied offset-only.
# Verified on the v0.21.6 bump: 8 x `patch -p1` on a pristine 818c13be tree -> rc=0,
# zero fuzz, zero .rej/.orig, all 13 touched files byte-identical to the authored tree,
# py_compile + compileall(agent/gateway/tools/hermes_cli) clean, and 38 functional
# assertions across 007/011/014/015/016/018/032 on the freshly applied tree.
#
# 033 ADDED same day (2026-10-09), after the sweep above, roster 8 -> 9: v0.21.6 turned
# enabled plugins into uv workspace members, and pm/workspace.py::_workspace_member()
# writes `[project] name = hermes-plugin-<key>` onto a "virtual" member (no
# [build-system], no tool.uv.package) without ever ensuring a `version`. hermes-lcm
# ships a tooling-only pyproject.toml (only [tool.ruff], no [project] at all), so the
# generated member had a [project] table with a name and no version and uv refused the
# WHOLE workspace: "uv lock exited 2: ... the required project.version field is neither
# set nor present in the project.dynamic list". Every plugin enable/install/update in
# the home then fails with AdmissionRefused, and the left-core migration could not
# install the Home Assistant plugin, leaving `platform 'homeassistant' references
# unknown toolset 'hermes-homeassistant'` behind it. 033 gives the generated virtual
# member the same "0.0.0" placeholder the manifest-only branch already writes, unless
# the plugin declares a static or dynamic version. Local fix: upstream main carries the
# same code (diffed 2026-10-09), so there is nothing to cite upstream yet.
# Verified: `patch -p1` rc=0 on a pristine 818c13be tree (no fuzz, no .rej/.orig,
# py_compile + check_structure clean), and end-to-end in
# ghcr.io/keivry/hermes-office:latest with the file bind-mounted over the image copy:
# `hermes plugins enable hermes-lcm` fails with the production error without it and
# completes (lock + install + enable) with it, generating a member pyproject carrying
# name + version = "0.0.0".
#
# 034 ADDED 2026-10-09, roster 9 -> 10 (a BACKPORT, not a local invention): upstream 51609d82
# ("fix(solstice): load the transport on first use, not at discovery (#134233)", committed
# 2026-10-08T22:06Z) is newer than our base, so the image ships the noise it fixed. The bundled
# solstice provider imported `.transport` at module level, and that transport imports
# agent.gemini_native_adapter, which does a module-level `import httpx`. The PM worker runtime
# (/opt/hermes/pm-runtime, include-system-site-packages=false, deliberately carrying no
# application dependencies) has no httpx, and the left-core migration / dependency sync imports
# hermes_cli.config, which discovers model-provider plugins on import -- so every boot logged
# "Failed to load bundled provider plugin solstice: No module named 'httpx'" on an otherwise
# clean start. That was worse than cosmetic: the lean runtime registered 49 providers instead of
# 50, i.e. the whole solstice profile was dropped, not just its HTTP client. (The gateway venv
# has httpx 0.28.1 and always loaded it fine -- nothing was broken in the real runtime.) 034
# moves INFERENCE_BASE_URL into the package __init__ -- the only thing discovery needs from the
# transport module -- and imports SolsticeClient inside SolsticeProfile.create_client(), so the
# plugin imports wherever profiles are discovered and the transport loads on first use, in a
# process that has the app's HTTP stack.
# RETIRED on the 2026-10-13 (v0.21.7) bump -- see that sweep block above:
# compare/v0.21.7...51609d82 == "behind" and the tagged source carries the same fix, so
# this file was deleted from patches/.
# NOT carried from the same commit: transport.py's `Dict[str, str]` -> `dict[str, str]`
# annotation normalization (unrelated and cosmetic).
# Verified: `patch -p1` rc=0 on a pristine 818c13be tree (no fuzz, no .rej/.orig, py_compile +
# ruff clean, AST assertions on INFERENCE_BASE_URL's single home and the lazy import), and
# end-to-end in ghcr.io/keivry/hermes-office:v0.21.6 with the pair bind-mounted over the
# installed copies: pm-runtime `import hermes_cli.config` prints the warning and reports 49
# providers / solstice absent before, and prints nothing with 50 providers / solstice registered
# after; the gateway venv still reports 50 providers and create_client(api_key=...) returns a
# SolsticeClient on https://generativelanguage.googleapis.com/v1alpha.
#
# 035 ADDED 2026-10-12, roster 10 -> 11 (a LOCAL feature gap, nothing upstream to cite): the
# Matrix adapter only routes a human reaction to the built-in reaction PROMPTS it is currently
# waiting on (in-memory registry, default expires_at 300s), and it silently drops everything
# else; there is no way for an out-of-tree consumer to be told about a click, and no signal at
# all for "un-reacted". The todo/reminder system needs exactly that: a reminder message sent at
# 09:00 must still complete the item when the capsule is clicked hours later, and un-clicking it
# (a removed reaction) must undo the completion. 035 forwards human reactions that no built-in
# prompt claims to the official `set_reaction_handler` hook as `reaction:added`, and handles
# `m.room.redaction` as `reaction:removed` -- Matrix has no "un-react" event, so removing a
# reaction IS a redaction of the reaction event and the payload carries the redacted event id
# (`redacts`). Out-of-tree consumers therefore get a stable contract: reaction payload fields
# `reaction` / `message_ts` / `event_ts` / `redacts`. The built-in prompt path is untouched
# (claimed reactions never reach the hook), so approvals and other prompts behave as before.
# RETIRE if upstream ever routes unclaimed reactions to a public hook.
# Verified on a pristine 818c13be tree: `patch -p1` rc=0 (no fuzz, no .rej/.orig), reverse
# `--dry-run` rc=0, py_compile clean, ruff check + ruff format clean on the added lines, and
# check_structure.py asserts the structural delta exactly -- MatrixAdapter 125 -> 127 methods,
# 1 new top-level function, no class-body indentation drift.
# 2026-10-13 sweep (rc.15-v0.21.7 / v0.21.7): roster 11 -> 10. This is the base that
# carries the dependency-generation fix this deployment was waiting for -- upstream
# fe2b130b, shipped in v0.21.7: pm/recovery.py::_baseline_gaps() compares the image's
# baked extras against the recorded selection and restores whatever is missing on boot
# (VERIFIED in the tagged source: 2 hits in pm/recovery.py of a v0.21.7 tree).
# Drift was checked, not assumed: (a) every patch real-applied to a pristine v0.21.7
# tree in lexicographic order, (b) upstream issue/PR state plus merge-commit ancestry vs
# v0.21.7, (c) each flagged bug still present in the tagged source, (d) a per-patch
# intent assertion on the freshly applied tree.
# 034 RETIRED -- the backport landed. `gh api compare/v0.21.7...51609d82` == "behind"
#   (the fix commit IS an ancestor of the tag); the tag's
#   plugins/model-providers/solstice/__init__.py carries INFERENCE_BASE_URL at module
#   level and imports SolsticeClient inside create_client() (line 49), and a real
#   `patch -p1` reports "Reversed (or previously applied) patch detected" -- exactly the
#   retire condition the 034 block below named. Nothing left to fix, nothing to apply.
# 011 KEPT, RE-ANCHORED. #85207/#85285 still OPEN, and recover_interrupted_turns() still
#   promotes a FRESH marker to resume_pending without asking whether the owning PID is
#   alive -- the detached-restart double loop is still reachable. Exactly one hunk (#4)
#   failed, on a pure text drift: upstream now writes `datetime.now(UTC)` where the
#   patch rewrote `datetime.now(timezone.utc)` at the same call site. The hunk was
#   re-authored against the tagged line (fuzz 0 now, no .rej). Also dropped the quotes
#   from the new helper's `entry: "SessionEntry"` annotation: the file carries
#   `from __future__ import annotations`, so ruff UP037 flags them -- the previous sweep
#   shipped them, ruff check is clean now.
# 016 KEPT, RE-ANCHORED (the user chose rewrite over retire). #65349/#83036 still OPEN
#   and upstream still has NO _repair_bare_repo_dirs anywhere in the tree (`grep -rn` = 0
#   hits, while v2026.9.24 still defined it) -- the patch can no longer lean on a
#   pristine definition and re-declares the helper, which is what it already did.
#   Exactly one hunk (#3) failed: upstream's subprocess.run() call grew `check=False,`.
#   The retry loop was re-authored around the new call. The premise is unchanged -- a
#   failed/timed-out gc still skips Pruner.reclaim()'s repair entirely.
# 033 KEPT as-is. v0.21.7 still writes `[project] name = hermes-plugin-<key>` onto a
#   virtual workspace member without ensuring a version
#   (pm/workspace.py::_workspace_member), and the patch still applies CLEAN -- itself
#   the proof it is unfixed: had upstream done it, the hunk would apply REVERSED like
#   034's did.
# 007/008/014/015/018/032/035 unchanged in substance, all re-applied at fuzz 0:
#   #77100 CLOSED-not-merged; #46365, #57546, #72515 and #72847 all CLOSED but with
#   mergedAt = null (never merged -- the trap this check exists for); #44347, #85713 and
#   #78888 still OPEN; 018's cited fix commit d4f6e5ac is "diverged" from v0.21.7 (not
#   an ancestor, so not in the tag); 032/033/035 cite no upstream issue at all.
# Verified on this bump: 10 x `patch -p1` on a pristine v0.21.7 tree -> rc=0, zero fuzz,
# zero .rej/.orig, and every touched file BYTE-IDENTICAL to the authored tree (`diff -r`
# clean). py_compile + compileall clean on all 15 touched files, ruff check clean,
# check_structure.py clean on both re-anchored files (session_lifecycle 13 -> 13 methods
# + the new top-level helper present; checkpoint_manager 20 -> 20 methods, no class-body
# nesting), plus 19 + 7 intent assertions on the re-anchored trees.
#
# 2026-10-14 sweep (v0.22.0 -- git tag e06df9c2, docker index digest
# sha256:c69536a39e885b8943329bda68cdf44492458b96aa74a212239bde9d2aeb406a): roster stays at
# 10. Base moved rc.15-v0.21.7 -> the bare `v0.22.0` tag. The window is narrow (v0.21.7
# tagger 2026-10-12T05:53:37Z -> v0.22.0 tagger 2026-10-14T03:21:39Z), so drift was checked,
# not assumed: (a) every patch real-applied to a pristine v0.22.0 tree in lexicographic
# order, (b) upstream issue/PR state plus merge-commit ancestry vs v0.22.0, (c) each flagged
# bug still present in the tagged source, (d) the per-file commit enumeration inside the
# window.
# NOTHING RETIRED AND NOTHING RE-ANCHORED -- the first sweep in this repo's record where no
# patch needed touching: every one applied at fuzz 0 with zero .rej/.orig, and the offsets
# that remain are pure context drift (007 +22, 008 +7/+15/+2, 011 -13, 014 +69, 015 +2,
# 018 +182/+64, 033 -11; 016, 032 and 035 applied dead-on). Ancestry agrees: #44347, #85207,
# #85285, #85713, #65354, #78888, #65349 and #83036 are all still OPEN, #77100 is still
# CLOSED-not-merged, and 018's cited fix commit d4f6e5ac is still "diverged" from the tag.
# Each premise was re-confirmed against the tagged source rather than inferred from those
# states: no `file_read` in toolsets.py (008); no active_turn_pid / active_turn_owner_alive
# anywhere in gateway/ or agent/ (011); title_generator.py still carries exactly one
# `extra_body={"response_format"` (014); no `node-compile-cache` in
# checkpoint_manager.DEFAULT_EXCLUDES (015); `_repair_bare_repo_dirs` still 0 hits tree-wide,
# so 016 keeps re-declaring it (016); no `_is_opencode_custom_name` (018);
# `_skill_diff_char_budget` absent while the flat `len(out) > 3000` cap still sits at
# gateway/slash_commands.py:917 (032); plugins/platforms/matrix/adapter.py still never calls
# `set_reaction_handler` and has no m.room.redaction handler (035).
# 033's retirement trigger is now NAMEABLE, and it is the interesting result of this sweep.
# Upstream main fixed the same gap on 2026-10-14T02:51:08Z (committer date) with 357986e58
# "fix(pm): give generated virtual workspace members a project.version" -- the exact change
# 033 makes -- widened by 3d8dfc1da "fix(pm): stage a version for version-less buildable
# plugin members too", which hoists the staging OUT of `if virtual:` so buildable members
# are covered too (a superset of 033). The v0.22.0 tag carries NEITHER: `gh api
# compare/v0.22.0...357986e58` == "diverged" and `compare/v0.22.0...main` == "ahead by 119 /
# behind 0", i.e. both commits are ancestors of main and NOT of the tag (they landed on main
# after the release branch was cut). The tagged source settles it -- pm/workspace.py:273-274
# still sets only [project].name in the virtual branch, and line 284's `version = "0.0.0"`
# belongs to the DIFFERENT manifest-only plugin-deps path further down, which is precisely
# the template 033's header names.
# => 033 STAYS on v0.22.0. RETIRE IT on the first base bump whose tag contains 357986e58:
#    the tell is the `if virtual:` branch staging a project.version (or 033 applying REVERSED).
# Verified on this bump: 10 x `patch -p1` on a pristine v0.22.0 tree -> rc=0 on every patch,
# fuzz=0, FAILED=0, REVERSED=0, zero .rej/.orig, all 15 touched files py_compile clean -- and,
# because that tree was not the one shipped, the built image (hermes-office:test-v0.22.0, from
# this Dockerfile) was exercised end to end: s6 boot with all five cont-init hooks green,
# gateway up under s6 with restarts=0, the cron ticker firing a probe job on schedule, 59
# plugins discovered / 55 enabled with all six of this home's plugins loaded, a real
# api_server session logging `Memory provider 'clawmem' registered (5 tools)` + `activated`,
# and every boot-time dependency re-resolution (pm/recovery.py::_baseline_gaps) exiting 0.
#
# 2026-10-15 sweep (v0.22.1 -- git tag 297552a9, claimTag rc.5-v0.22.1, docker index digest
# sha256:861c9756ed6c558530c73d5c27860343b00c0d5efd6997a1d8ec6416c8a2b485 == stable == latest,
# release published 2026-10-14T23:59:24Z): roster 10 -> 9.
# 033 RETIRED -- this is exactly the base bump the v0.22.0 sweep named as its retirement
#   trigger ("RETIRE IT on the first base bump whose tag contains 357986e58"). The trigger
#   fired: `gh api compare/v0.22.1...357986e58` == behind 2213, `...2a10164cd` == behind 2212,
#   `...3d8dfc1da` == behind 2211 -- all three fix(pm) commits are ancestors of the tag, so
#   the fix IS in v0.22.1. The tagged source confirms it at the level 033 anchored to:
#   pm/workspace.py stages the placeholder version OUTSIDE the `if virtual:` branch
#   (line 281: `if project is not None and "version" not in project and "version" not in
#   project.get("dynamic", ()): project["version"] = "0.0.0"`), i.e. 3d8dfc1da's superset
#   form, while line 274 still only writes [project].name for the virtual branch. A real
#   `patch -p1 --dry-run` of 033 on a pristine v0.22.1 tree now reports "Hunk #1 FAILED at
#   283", and the REVERSE dry-run fails too (upstream reworded the surrounding block), which
#   is the "content superseded" state rather than the "already applied" one. Upstream also
#   generalized the guard: 033 skipped a member that declared ANY version (static or in
#   project.dynamic) by keeping the old manifest-only path; v0.22.1 checks `dynamic`
#   explicitly, which is the PEP 621-correct form.
# THE OTHER NINE all KEEP and needed no re-anchoring: 007, 008, 011, 014, 015, 016, 018, 032,
#   035 re-applied in lexicographic order at fuzz 0 with zero .rej/.orig. (016 alone reports
#   FAILED when dry-run on its own -- it depends on 015's _ensure_store_excludes(), exactly as
#   its header says; in the real ordered apply it lands clean. This is the
#   sequential-patch-dependency trap, not drift.)
# Each premise was re-confirmed against the tagged source, not inferred from issue state:
#   no `file_read` in toolsets.py or hermes_cli/setup_quick.py (008; #44347 still OPEN);
#   no active_turn_pid / active_turn_owner_alive anywhere under gateway/ or agent/ (011;
#   #85207/#85285 still OPEN -- upstream still keys off _is_fresh_gateway_interruption with
#   the old _set_turn_marker_locked signature); exactly one
#   `extra_body={"response_format"` left in title_generator.py, i.e. still unconditional (014);
#   no node-compile-cache/ in checkpoint_manager.DEFAULT_EXCLUDES (015; #78888 OPEN);
#   `_repair_bare_repo_dirs` still 0 hits tree-wide (016; #65349/#83036 OPEN);
#   no `_is_opencode_custom_name` (018, office-specific); `_skill_diff_char_budget` absent
#   while the flat `len(out) > 3000` cap still sits in gateway/slash_commands.py (032);
#   plugins/platforms/matrix/adapter.py still never calls `set_reaction_handler` and has no
#   m.room.redaction handler (035).
# 014 NOTE (premise narrowed, patch KEPT): upstream's 3c675019f landed in this tag and gave
#   the auxiliary client a `_is_structured_output_rejection` retry ladder plus a DeepSeek
#   profile declaring `unsupported_response_formats=("json_schema",)`, and title generation
#   routes through that client -- so an unconditional response_format is no longer a HARD
#   failure. It is still a guaranteed-wasted round trip per session, and #85713 (retry
#   cascade) is still OPEN, which is the condition 014's header names ("Keep until #85713
#   merges upstream"). Not retired on this bump; revisit when #85713 lands.
# VERIFIED on this bump: 9 x `patch -p1` in lexicographic order on a pristine v0.22.1 tree
#   (83 MB tarball from codeload) -> rc=0 on every patch, fuzz=0, zero .rej/.orig, all 14
#   touched files py_compile clean, and 9/9 mechanism assertions PASS on the freshly applied
#   tree (one grep per patch on the symbol the patch was written around). The clawmem roster
#   was checked too: the CLAWMEM roster's own 036 (src/limits.ts, src/llm.ts, src/splitter.ts) still
#   exist in clawmem 0.43.3 and the patch dry-runs clean against the packed tarball.
#
# 2026-10-15 (no base bump; still v0.22.1): roster 9 -> 10. 036 ADDED --
#   matrix-path-like-slash-text-is-not-a-command. A live failure on this deployment
#   (RuntimeStoreError('invalid_params') at 16:19:03 / 16:19:25 / 16:25:23 / 16:25:42 / 16:59:11,
#   two Matrix DM rooms, every failing body a "/"-prefixed message whose first token contains a
#   slash) traced to the Matrix adapter stamping MessageType.COMMAND from a bare leading "/":
#   MessageEvent.get_command() deliberately returns None for a path-like token, the router enters
#   the admission lane exactly when get_command() is falsy, and v0.22.1's durable native admission
#   refuses a COMMAND-typed event that is not a command -- so ordinary text about a path died
#   before any turn ran, while real slash commands were dispatched as commands and were fine.
#   The fix derives the stamped type from the router's own classifier instead of re-testing the
#   prefix. NOT an upstream PR: upstream main still carries the bare-prefix test as of 2026-10-15
#   and no issue covers it (#138895/#138896 are the unrelated Mattermost media_urls case; the
#   prefix test also exists in slack/discord/mattermost/weixin/relay, untouched here).
# VERIFIED: 10 x `patch -p1` in lexicographic order on a fresh pristine v0.22.1 tree -> rc=0 on
#   every patch, fuzz=0, zero .rej/.orig (036's second hunk lands at offset +16, expected: 007 and
#   035 both insert above it), adapter.py py_compile clean, marker `def _matrix_command_message_type(`
#   present exactly once and zero leftover `MessageType.COMMAND if body.startswith`, plus a real
#   behavioural red/green on that same applied tree: with 036 reverse-applied the 3 path-like bodies
#   fail (typed COMMAND, which _validate_native refuses) and with it applied they pass, the 4
#   command-shaped bodies (real slash commands plus resolved and unresolved bang text) keep their
#   previous type either way, and the 3 existing Matrix suites stay at 140 passed. The throwaway
#   test module is NOT shipped -- this roster carries runtime files only.
#
# 2026-10-16 sweep (v0.22.2): roster 10 -> 11. This tag is a release cut from release/0.22.1
#   with the published v0.22.1 as its parent (d923a5eb) -- it is what 0.22.1 was meant to ship;
#   0.22.1 was built from the wrong commit. Drift was checked, not assumed: every patch
#   real-applied to a pristine v0.22.2 checkout in lexicographic order -> rc=0 on all 11, fuzz=0,
#   zero .rej/.orig, all 16 touched files py_compile clean, ruff check clean before AND after on
#   the two files 037 touches, check_structure.py STRUCTURE OK, and 11/11 marker greps present.
#   ZERO RETIRE (no patch's fix is in v0.22.2) and ZERO RE-ANCHOR (offset-only drift; the largest
#   was 018's +187 in chat_completion_helpers.py). 016 again reports a standalone FAIL purely
#   because it depends on 015 -- it applies clean in lexicographic order.
#
#   Upstream-coverage check per patch on this bump: the referenced upstream items are
#   #46310/#57315/#85207/#105841/#82816/#85713 (CLOSED-mixed: 011's #85207 is still OPEN and its
#   fix is NOT in the tag; 014 stays because #85713 is still OPEN per its own header condition),
#   #78888/#65349/#83036 (all still OPEN -> 015/016 stay), 035/036 (local gaps, upstream main still
#   carries the unfixed shape: adapter.py:2166 still stamps MessageType.COMMAND from a bare leading
#   "/", and there is still no set_reaction_handler call). No ancestry flip on any of them.
#
#   037 ADDED (roster 10 -> 11): deepseek-responses-reasoning-text-echo, a vendored upstream
#   PR #133799 (still OPEN/DRAFT; issue #133792 still OPEN) rebased onto v0.22.2 PLUS a fix to the
#   PR's own gate. The PR gates both call sites on needs_reasoning_echo(None, None, base_url),
#   which matches the must-echo table on host OR model; DeepSeek's host entry is api.deepseek.com
#   only and this deployment reaches DeepSeek through the OpenCode Go relay (opencode.ai), so with
#   provider/model dropped the family never matches and the pad never engages. Measured on the
#   v0.22.2 tree: (None, None, relay) -> False; ("custom", "deepseek-v4.1-flash", relay) -> True.
#   Both call sites now pass provider + model. Without that deviation this patch is inert here.
#   Full rationale, the RED->GREEN evidence and the retirement condition are in the patch header.
#
#   038 ADDED on 2026-10-16, NO base bump (roster 11 -> 12):
#   deepseek-responses-orphan-turn-reasoning-synthesis. Same 400 as 037, DIFFERENT root cause, so
#   it does NOT retire 037 -- both apply. 037's setdefault pad is a no-op on a turn that persisted
#   no reasoning sidecar at all (_capture_encrypted_item returns None without an encrypted_content
#   blob, and the relay only mints one when the request carries include:["reasoning.encrypted_content"]),
#   so that turn replays zero items and the relay rejects every further continuation of the session.
#   Measured on the real failing history (session 20261016_082835_80b44738, 473 input items): 17 of
#   106 assistant turns replay zero items; only the LAST one is decisive. Synthesizing the first
#   orphan, or all but the last, still 400s; synthesizing the last, or all, flips to 200. Padding any
#   existing item (all 89, first, last, real text, one char, no blob) stays 400, and dropping all
#   reasoning items stays 400 -- the pad route cannot reach the failing turn. Text must be non-empty
#   ("" and summary-only both 400). H1 synthesizes the missing item inside _replay_reasoning_items
#   (placement is load-bearing: inserting into the post-conversion `items` list breaks
#   function_call/function_call_output pairing and yields "No tool output found ..."), H2 makes
#   _preflight_encrypted forward a reasoning item that has content but no blob (complementing 037,
#   which covers the HAS-blob branch). Runtime file: agent/codex_responses_adapter.py alone.
#   Gate: reuses 037's needs_reasoning_echo(provider, model, base_url) call sites unchanged.
#   Full rationale, the end-to-end evidence and the retirement condition are in the patch header.
#
#   VERIFIED for 038 (2026-10-16): all 12 x `patch -p1` forward-applied in lexicographic order on a
#   fresh pristine v0.22.2 tree -> rc=0 on every patch, fuzz=0, zero .rej/.orig, and the resulting
#   agent/codex_responses_adapter.py md5 8a537bfda34d2d1d3a87a46cce29655f -- the exact tree the
#   end-to-end run below exercised. Behaviour: real failing history through the REAL converter +
#   preflight, gate OFF -> HTTP 400 reasoning_text; gate ON -> HTTP 200 completed (+17 items = the
#   17 orphan turns); short-history regression -> HTTP 200. ruff check (project ruff.toml) clean
#   before and after on the touched file; E501 is not in this repo's ruff select, so the added
#   comment lines' length is not a defect. The file is not ruff-format-clean upstream (166 would-
#   reformat hunks in the pristine file) and 038 adds only 2 more of the same kind, so no format
#   gate is applied to it -- consistent with the file's existing style, e.g. _preflight_encrypted's
#   own multi-line boolean continuation.
#
# VERIFIED on this bump: 11 x `patch -p1` in lexicographic order on a fresh pristine v0.22.2 tree
#   -> rc=0 on every patch, fuzz=0, zero .rej/.orig, all 16 touched files py_compile clean,
#   11/11 marker greps PASS, ruff check clean on 037's two files before and after, and
#   check_structure.py STRUCTURE OK on both. 037 additionally carries a behaviour-level RED->GREEN
#   through the real transport call path plus an end-to-end replay of the real failing history.
#
# Previous sweeps:
# v0.22.0 / e06df9c2 (2026-10-14): roster stayed at 10, zero retire / zero re-anchor. See the
#   dedicated v0.22.0 block above for 033's then-unmet retirement trigger.
# v2026.9.14 / v0.21.3: roster stayed at 8; 7 of 8 re-applied offset-only and
#   014 was re-anchored (upstream inserted reasoning_config={"enabled": False}
#   at its call site).
# v2026.9.11 / v0.21.2: all 8 re-anchored after upstream's decomposition moved
#   007 -> tools/send_message_senders.py, 008 -> hermes_cli/setup_quick.py,
#   011 -> gateway/session.py + session_lifecycle.py + run_startup.py, and 018
#   onto a rewritten agent/opencode_affinity.py.
# RETIRED at v2026.9.21 — 004 (narrow direct_api_call streaming). Its premise is
#   gone. It returned False for non-openrouter/nous providers so cron/delegation
#   turns kept the streaming wire, because at authoring time
#   should_use_direct_api_call()==True meant the NON-streaming path. Upstream
#   #100906 (c5b99a3, verified an ancestor of the tag) now routes those contexts
#   to interruptible_streaming_api_call instead: the request still runs INLINE on
#   the conversation thread (the #62151 nested-pool deadlock stays closed) but
#   STREAMS on the wire, which is exactly the liveness property 004 wanted.
#   #71268 is CLOSED as fixed by that commit. Keeping 004 would now be actively
#   harmful: returning False pushes a custom-provider cron turn back onto a
#   worker thread (_NonStreamRequest is documented as "on a worker thread"),
#   reintroducing the nested-pool wedge.
# 007 = upstream #77100 (CLOSED, not merged): Matrix adapter loop-mismatch
#   bridge — keep until #77100 merges upstream.
# 008 = upstream #44347 (open): file_read toolset (read-only subset of file:
#   read_file + search_files, NO write/patch) — sandboxed read-only agents
#   (skill-audit) can inspect files without a write path. Trimmed to the 3
#   runtime files (toolsets.py / hermes_cli/setup_quick.py /
#   hermes_cli/tools_config.py); PR tests/website hunks excluded (not shipped
#   in the production image — including them makes `patch` fail and abort the
#   build). Keep until #44347 merges upstream.
# 011 = upstream #85207 (open): gateway restart mid-turn can spawn TWO parallel
#   conversation loops on one session (detached restart overlap), duplicating
#   the whole history and delivering divergent finals. Durable active-turn
#   marker now records the owning gateway PID; boot recovery/auto-resume refuse
#   to start a second loop while the owner is alive (PR #85285, open). Keep
#   until #85285 merges upstream. RE-ANCHORED on the v2026.9.21 bump: upstream
#   added a `transport_profile` argument to the SessionEntry(...) constructor,
#   which drifted only hunk #4's trailing context (the single
#   `model_override=..., **plain` line became three).
#   RE-ANCHORED AGAIN on the v0.21.6 bump: upstream grew its own turn-marker
#   pair and `_set_turn_marker_locked` now takes (session_key, entry, token,
#   started_at) with an aware-UTC timestamp, and the auto-resume freshness test
#   became `_is_fresh_gateway_interruption(...)`. Both are context-only drifts
#   for 011 -- the old patch still applied, but with fuzz 2 on two hunks, which
#   is why it was regenerated rather than shipped as-is.
#   RE-ANCHORED AGAIN on the v0.21.7 bump: upstream switched that same call site to
#   `datetime.now(UTC)`, which is the exact line hunk #4 rewrites, so the hunk was
#   re-authored against the tagged text. The new helper's annotation also lost its
#   quotes (UP037 -- `from __future__ import annotations` is in the file).
# 014 = upstream #82816/#85713 (open): title_generator unconditionally sent
#   OpenAI-only response_format json_schema strict -> Console Go / DeepSeek /
#   Anthropic all 400 ("This response_format type is unavailable now") on every
#   fresh session. This patch drops response_format entirely; _extract_title_text
#   already falls back through JSON-dict -> loose regex -> prose+think-strip, so
#   titles still work. Keep until #85713 (retry-cascade) merges upstream.
#   RE-ANCHORED on the v2026.9.21 bump: upstream's call site is now
#   `max_tokens=TITLE_MAX_TOKENS, temperature=None` (was `64` / `0.3`), which
#   drifted only hunk #2's leading context. Upstream STILL sends
#   response_format unconditionally (now line ~456), so the patch is unchanged
#   in substance.
# 015 = upstream #78888 (open): checkpoint_manager DEFAULT_EXCLUDES missing
#   node-compile-cache/ — the desktop/TUI launcher writes this cache (can be
#   root-owned) into <workdir>/tmp/node-compile-cache/, so `git add -A` aborts
#   with Permission denied (rc=128) and affected workdirs get zero checkpoints.
#   Adds the exclude + _ensure_store_excludes() so existing stores also pick it
#   up. Trimmed to tools/checkpoint_manager.py (PR tests excluded). Keep until
#   #78929/#78944 merge upstream. RE-ANCHORED on the v0.21.6 bump: upstream
#   reformatted DEFAULT_EXCLUDES to one pattern per line with a comment per
#   group and reshaped _init_store, so both the list hunk and the init hunk were
#   rewritten. _ensure_store_excludes() is now append-only (an operator's own
#   lines in info/exclude are preserved) and is also called on the
#   existing-store path, which upstream never refreshes.
# 016 = fix(checkpoints): bare-store self-heal for `fatal: not a git repository:
#   '/.../checkpoints/store'`. git's is_git_directory() requires HEAD plus an
#   objects/ and a refs/ directory; when the store loses one of them every command
#   fails — including the `git gc` of the next prune, so the store can never repair
#   itself and every checkpoint silently fails. This deployment logged exactly that
#   on 2026-08-21 (errors.log.2: `git add -A` rc=128, spamming for over an hour).
#   The patch adds a proactive mkdir-if-missing before every git call in _run_git, a
#   retry-on-fatal that self-heals once and re-runs, and an early repair when
#   _init_store opens an existing store.
#   v0.21.6 owns the same repair but reaches it from a worse place: gc moved into
#   checkpoint_pruning.Pruner.reclaim(), after a `_git()` that RAISES on failure, so a
#   failed or timed-out gc now skips the repair entirely (v2026.9.24's _gc_store()
#   called it through a _run_git() that never raised). See the sweep paragraph above.
#   An earlier draft of this comment blamed `git gc` for deleting an empty refs/heads/;
#   that is NOT reproducible (git 2.47.3 keeps the dir on gc and on pack-refs --prune)
#   and was dropped rather than shipped. Refs: #65349 (concurrent gc),
#   #79334/#79335 (size-cap loop), #83036 (GC tmp packs/corruption), local 015/#78888.
#   Depends on 015: its _init_store hunk calls _ensure_store_excludes(), which 015
#   defines — add and remove the two together. Keep until upstream merges the
#   bare-repo-dir fix.
#   RE-ANCHORED AGAIN on the v0.21.7 bump, and REWRITTEN rather than retired (the
#   user's call): upstream deleted _repair_bare_repo_dirs from the tree entirely (0 grep
#   hits vs v2026.9.24), so the patch keeps re-declaring it, and hunk #3 was re-authored
#   around the new `check=False,` in subprocess.run(). The premise held -- the store a
#   failed gc leaves behind still has no repair path of its own.
# 018 = hermes-office specific (NOT upstream): named custom providers fronting
#   the relay (custom:opencode -> proxy IP) flatten to provider "custom" at
#   runtime, so is_opencode_target misses on BOTH signals; thread
#   requested_provider through and match the name against the whole
#   `opencode` / `opencode-*` namespace after stripping the `custom:` prefix
#   (_is_opencode_custom_name). Since v2026.9.11 upstream's is_opencode_target
#   ALSO matches by base_url host "opencode.ai", so 018 is a no-op for
#   providers pointed at opencode.ai and only earns its keep for a base_url
#   elsewhere (the commented-out internal proxy). The family check still runs
#   first: hermes_cli.models stays the single owner of the canonical families.
#   RE-ANCHORED and KEPT on the v2026.9.21 bump: upstream rewrote the module
#   (merge_opencode_session_headers -> merge_session_affinity_headers) and added
#   an opt-in `providers.<name>.session_affinity_header` config knob (documented
#   in the README section "Custom providers fronting the OpenCode relay"). The
#   knob was NOT treated as a replacement, because it has no `oneshot-<hex>`
#   fallback: a relay that hard-requires the header (OpenCode Go 400s with
#   MissingSessionID, #105841) would still see headerless stateless requests.
#   The knob is also matched by base_url route, so it covers only entries the
#   operator explicitly annotates. 018 matches by NAME, so it stays effective
#   for any base_url. Revisit if upstream gives the knob the same fallback.
# 032 = hermes-office specific (NOT upstream, and no upstream issue either):
#   gateway/slash_commands.py caps `/skills diff` at a flat 3000 chars for every
#   platform, while the delivery adapters declare far larger single-message limits
#   (Matrix _SPLIT_THRESHOLD = max_message_length - 100 = 15900, Feishu 4000,
#   Discord 1900). A staged batch that renders completely (~6.6 KB for 2 ops)
#   therefore arrives truncated on the one platform that could carry it in a single
#   message. The same block also points users at ~/.hermes/pending/skills/<id>.json,
#   which does not exist when HERMES_HOME is not ~/.hermes (this deployment:
#   /opt/data); v0.21.6 moved that sentence into locales/*.yaml while keeping the
#   wrong path, so 032 post-processes the rendered note and re-points it.
#   _skill_diff_char_budget() reads the adapter's own _SPLIT_THRESHOLD, falls back to
#   max_message_length - 100, then to 3000, and returns max(3000, limit) — widening
#   only, so no platform is ever handed a smaller diff than it got before.
# NOTE: --no-backup-if-mismatch is required, not cosmetic. GNU patch's default is
# --backup-if-mismatch, so every patch that applies with an offset (007/008/014/018
# do) leaves a <file>.orig copy next to the patched file in /opt/hermes.
COPY patches/ /tmp/hermes-patches/
RUN set -eux; \
    if ls /tmp/hermes-patches/*.patch >/dev/null 2>&1; then \
        for p in /tmp/hermes-patches/*.patch; do \
            echo "==> Applying $(basename "$p")"; \
            (cd /opt/hermes && patch -p1 --no-backup-if-mismatch < "$p"); \
        done; \
    fi; \
    rm -rf /tmp/hermes-patches

# ── ClawMem package patches ──────────────────────────────────────────────
# ClawMem is a global npm install (/usr/local/lib/node_modules/clawmem), not
# part of the Hermes source tree, so the roster above cannot reach it:
# patches/clawmem/*.patch are applied here, against the installed package root,
# in lexicographic order. Same contract as above -- a patch that does not apply
# exits nonzero and aborts the build (which is also the retirement signal: a
# clawmem bump that fixes the bug upstream makes the anchored patch fail), and
# `ls patches/clawmem/*.patch | wc -l` is the truth, not any prose count.
# Applied after the CLAWMEM_VERSION install above and before any runtime use;
# the glob above matches files only, so it never picks these up. Retire the
# patch together with the ENV/script workarounds it supersedes.
COPY patches/clawmem/ /tmp/clawmem-patches/
RUN set -eux; \
    CLAWMEM_PKG=/usr/local/lib/node_modules/clawmem; \
    test -f "$CLAWMEM_PKG/src/llm.ts"; \
    if ls /tmp/clawmem-patches/*.patch >/dev/null 2>&1; then \
        for p in /tmp/clawmem-patches/*.patch; do \
            echo "==> Applying $(basename "$p") (clawmem pkg)"; \
            (cd "$CLAWMEM_PKG" && patch -p1 --no-backup-if-mismatch < "$p"); \
        done; \
    fi; \
    rm -rf /tmp/clawmem-patches

COPY skills/ /opt/hermes/skills/
# s6-overlay cont-init.d hook: runs after base stage2 setup (01-hermes-setup),
# handles rtk-rewrite plugin enablement, ClawMem plugin sync, and ClawMem
# sidecar autostart.
COPY docker/cont-init.d/ /etc/cont-init.d/

USER root

# Create venvs as root — chown back to hermes so runtime access works.
# NOTE 1: uv 0.11+ in base v2026.8.19 defaults to downloading CPython 3.11 when
#         no --python is given, which breaks the cp313 torch wheels. Pin 3.13.
# NOTE 2: base images since v2026.8.19 set [tool.uv] exclude-newer = "14 days" in
#         /opt/hermes/pyproject.toml. Since the Dockerfile inherits WORKDIR
#         /opt/hermes, uv resolves that config and refuses packages published
#         in the last 14 days (e.g. docling 2.124.0). Run from /tmp to bypass.
RUN cd /tmp \
    && uv venv --python 3.13 /opt/tools/ppt-master/.venv \
    && uv pip install --python /opt/tools/ppt-master/.venv/bin/python --no-cache-dir -r /opt/tools/ppt-master/requirements.txt \
    && mkdir -p /opt/tools/docling \
    && uv venv --python 3.13 /opt/tools/docling/.venv \
    && uv pip install --python /opt/tools/docling/.venv/bin/python --no-cache-dir \
        "${TORCH_CPU_WHL}" "${TORCHVISION_CPU_WHL}" \
    && uv pip install --python /opt/tools/docling/.venv/bin/python --no-cache-dir \
        "docling==${DOCLING_VERSION}"

# Root-owned venv files under /opt/tools — chown to hermes for runtime access.
# This is the last uv consumer in the build, so drop the build-only uv shim.
RUN chown -R hermes:hermes /opt/tools \
    && rm -f /usr/local/bin/uv

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
    && test -x "${CLAWMEM_BIN}" \
    && test -f /opt/tools/clawmem-plugin/plugin.yaml \
    && node -e 'const fs=require("fs"); const pkg=JSON.parse(fs.readFileSync("/usr/local/lib/node_modules/clawmem/package.json","utf8")); console.log(`clawmem ${pkg.version}`)' \
    && rtk --version \
    && gh --version \
    && git lfs version \
    && pdfcpu version \
    && qpdf --version \
    && pdfinfo -v \
    && if command -v magick >/dev/null 2>&1; then magick -version; else convert -version; fi
