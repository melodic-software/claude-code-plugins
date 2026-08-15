# Cloud fleet setup — one shared environment for every melodic-software repo

The goal-oriented companion to [CLOUD-SESSIONS.md](CLOUD-SESSIONS.md): that doc explains the
mechanics and this repo's own setup; this one gets **the whole fleet** runnable in Claude Code
cloud sessions (web, `claude --cloud`, mobile, desktop, and routines) with warm-boot startup.
Account context this plan is built for: a personal (Max) claude.ai account — organization-shared
and self-hosted environments are Team/Enterprise features and deliberately out of scope.

Basis and freshness: every repository row below was derived from a shallow clone of that repo's
default branch on 2026-08-13; platform claims rest on the rung-1 doc fetches recorded in
[CLOUD-SESSIONS.md](CLOUD-SESSIONS.md); the environment itself was verified live on 2026-08-14
from a cloud session inside it — results in [#2654](https://github.com/melodic-software/claude-code-plugins/issues/2654),
folded in below. Recheck trigger, per the
[upstream-drift convention](conventions/upstream-drift/README.md): a repo changes its toolchain
pins (`global.json`, `.node-version`, `.python-version`, lockfiles) or its `.claude/` config, or
a verification session (see [checklist](#verification-checklist)) contradicts a row.

## The design in one paragraph

Cloud environments are account-scoped and repo-agnostic, and each environment's setup script
result is cached as a filesystem snapshot (the "warm boot": script runs once, later sessions boot
from the snapshot; rebuilds only on script/network edits or ~7-day expiry). So the fleet uses
**one shared environment** whose setup script installs the *union* of static toolchains the
repos pin — .NET SDKs, Node 24, `gh`, PowerShell — inside the ~5-minute cache-build budget, while
**each repo owns its own bootstrap** in a committed, idempotent, `CLAUDE_CODE_REMOTE`-guarded
SessionStart hook that installs manifest-driven dependencies (`npm ci`, repo-local .NET, `uv
sync`). The environment stays generic; repos opt in by adopting the hook pattern.

## Fleet audit (2026-08-13)

Pinned toolchains found: **.NET SDK 10.0.302** (medley, github-iac — `rollForward: disable`, so
the exact patch is required) and **10.0.400** (ci-workflows); **Node 24.18.0**
(medley, github-iac, provisioning, standards, dotfiles; codex-plugins pins major 24) — the cloud
VM ships Node 20/21/22 only, so this is always an install; **Python 3.14** (medley,
claude-code-proxy — the VM has `uv`, see the caveat below); **Go 1.26.6** (ci-runner — the VM's
Go plus the module `toolchain` mechanism covers this); **PowerShell** (`pwsh` — six repos carry
`PSScriptAnalyzerSettings.psd1`; ci-workflows also runs Pester) — not pre-installed.

| Repo | Stack / pins | `.claude/` today | Cloud needs beyond the shared env |
|---|---|---|---|
| claude-code-plugins | Node (`.node-version`), npm, ruff, lint pins | Full bootstrap hook **registered** (#2655), marketplace declared, full catalog enabled (#2631) | None — re-verify per the [checklist](#verification-checklist) |
| medley | .NET 10.0.302 (repo-local `.dotnet` supported), Node 24.18.0, Python 3.14, npm, Playwright visual CI | Rich guard/telemetry hooks, 54 plugins, 13 `.mcp.json` servers — **no dependency bootstrap hook** | Add bootstrap hook: .NET into `.dotnet`, `npm ci`, `uv sync`; Playwright browsers on demand |
| github-iac | .NET 10.0.302, Pulumi (C#), Node 24.18.0, npm | settings + CLAUDE.md, no bootstrap hook | Add bootstrap hook (.NET, `npm ci`); `pulumi` CLI only if sessions should run previews |
| ci-workflows | .NET 10.0.400, pwsh + Pester + PSScriptAnalyzer, Go fixtures | settings + CLAUDE.md, no bootstrap hook | Add bootstrap hook (.NET 10.0.400); pwsh comes from the shared env |
| ci-runner | Go 1.26.6, Docker | AGENTS.md only | Likely none — Go toolchain auto-resolves via `proxy.golang.org` (allowlisted) |
| claude-code-proxy | Python ≥3.14, uv (`uv.lock`), ruff, lefthook | none | Add bootstrap hook (`uv sync`); verify `uv python install 3.14` (caveat below) |
| provisioning | Node 24.18.0, npm, pwsh; content targets **Windows hosts** (winget runbooks) | settings + CLAUDE.md, no bootstrap hook | Add bootstrap hook (`npm ci`); sessions can lint/edit but never exercise Windows steps |
| standards | Node 24.18.0, npm, biome/ruff configs | settings + CLAUDE.md, no bootstrap hook | Add bootstrap hook (`npm ci`) |
| dotfiles | chezmoi-style user config (Windows-heavy), Node 24.18.0, pyproject | worktree helper hooks | Bootstrap hook optional (lint tooling). **Key fact: `dot_claude` content shapes `~/.claude`, which never reaches cloud sessions** — anything wanted in the cloud must be repo-committed or env-provided |
| knowledge-corpus | content (32 MB) | marketplace declared | None |
| songwriting | content | marketplace + `songwriting` plugin enabled — already the model citizen | None |
| codex-plugins | Node 24 (major), npm, tests | AGENTS.md only | Add bootstrap hook (`npm ci`) if cloud work is expected |
| cursor-plugins / claude-lane-sandbox / .github | content / sandbox / org meta | minimal | None |

Out of scope: the three archived repos, and `kyle-sexton/prereq-cancelled-verify` +
`kyle-sexton/autonomy-demo-scratch` (a session can attach repos from only one owner; audit those
from a session started on a `kyle-sexton` repo if they ever matter).

## Step 1 — the shared environment (claude.ai UI, one time)

> **Rollout direction (2026-08-15):** account rollout and per-repo migration prompts live in
> [prompts/cloud-bootstrap-rollout.md](../prompts/cloud-bootstrap-rollout.md). Fleet repos are
> renaming their committed bootstrap from `.claude/hooks/session-start.sh` to
> `.claude/cloud-bootstrap.sh` (one script, two callers — the environment's cache build
> pre-launch, and the SessionStart hook per session), so the standards `cloud-environment`
> component must invoke the new path where present and fall back to the old one. Pre-launch
> execution is what makes marketplace plugins load at turn one (see
> [CLOUD-SESSIONS.md](CLOUD-SESSIONS.md)).

Environments are created only from the environment selector at
[claude.ai/code](https://claude.ai/code) (cloud icon above the message box) — there is no API.
Either edit **Default** in place or add a new environment named e.g. **Melodic** so Default stays
pristine:

- **Network access**: **Custom**, with **Also include default list of common package managers**
  checked, plus these hosts: `dot.net`, `aka.ms`, `builds.dotnet.microsoft.com`,
  `download.visualstudio.microsoft.com`. This is a hard requirement, not a fallback: the 2026-08-14
  verification run ([#2654](https://github.com/melodic-software/claude-code-plugins/issues/2654),
  Blocker 1) reproduced the .NET installer's redirect chain being `403`-blocked under Trusted
  (session-side probes on 2026-08-13 had suggested the documented allowlist was conservative; the
  setup-script build proved otherwise). Trusted works only if the fleet ever drops .NET from the
  environment.
- **Environment variables**: none. There is no secrets store — anything here is readable by every
  session in the environment. `gh`/git auth comes from the GitHub proxy automatically.
- **Setup script**: paste only the three-line bootstrap below. The real script is the
  [`cloud-environment` component in standards](https://github.com/melodic-software/standards/blob/main/components/cloud-environment/setup.sh)
  (standards is the org baseline SSOT and is public, so the raw fetch needs no credentials and
  `raw.githubusercontent.com` is on the default allowlist) — edits to what environments install
  land there by reviewed PR, never by hand-editing this account-scoped UI field.

```bash
#!/bin/bash
curl -fsSL https://raw.githubusercontent.com/melodic-software/standards/main/components/cloud-environment/setup.sh \
  -o /tmp/melodic-env-setup.sh && bash /tmp/melodic-env-setup.sh
exit 0
```

What the canonical script does (details and lifecycle in the
[component README](https://github.com/melodic-software/standards/blob/main/components/cloud-environment/README.md)):
parallel tracks install `gh` + PowerShell (apt), the fleet's exact .NET SDK pins into
`/opt/dotnet`, and Node 24.18.0 via the VM's nvm; it then bakes the checked-out repo's own
SessionStart hook into the snapshot. Every step logs with a timestamp to
`/var/log/melodic-env-setup.log`, and `/opt/melodic-env-setup.done` (version + timestamp) is
written strictly last — so a missing stamp is the signature of an interrupted cache build
([#2654](https://github.com/melodic-software/claude-code-plugins/issues/2654) Blocker 2), fixed
by forcing a rebuild.

Two lifecycle caveats: the fleet's toolchain pins are duplicated into the component by necessity
(the script cannot read repos it isn't running in) — each repo's hook *also* installs its exact
SDK repo-locally, so the env copy is a warm cache and the hook is the correctness guarantee. And
a merged component change does **not** reach existing environments on its own: the snapshot
rebuilds only on an edit to the environment's script/network fields or ~7-day cache expiry, so
after a standards bump, force a rebuild with any trivial edit to the script field.

## Step 2 — per-repo templates

Two files per repo that needs dependencies. Both are committed, so every cloud session picks
them up from the clone; nothing depends on `~/.claude`.

**`.claude/settings.json`** — register the hook (merge into the existing file where one exists),
and declare the marketplace the way medley and songwriting already do (`github` source — resolves
in cloud sessions, unlike anything user-scoped):

```json
{
  "hooks": {
    "SessionStart": [
      {
        "matcher": "startup|resume",
        "hooks": [
          {
            "type": "command",
            "command": "bash \"$CLAUDE_PROJECT_DIR\"/.claude/hooks/session-start.sh"
          }
        ]
      }
    ]
  },
  "extraKnownMarketplaces": {
    "melodic-software": {
      "source": { "source": "github", "repo": "melodic-software/claude-code-plugins" }
    }
  },
  "enabledPlugins": { "<plugin>@melodic-software": true }
}
```

**`.claude/hooks/session-start.sh`** — manifest-driven, so one template serves the fleet; delete
the blocks a repo doesn't need. Design rules (same as this repo's production hook): cloud-only
guard, idempotent (hooks run on every startup *and* resume), warn-and-continue for anything the
session can limp along without, and `$CLAUDE_ENV_FILE` as the only way to shape the session's
environment (append `export`-lines, dedup-guarded):

```bash
#!/usr/bin/env bash
# SessionStart bootstrap — cloud sessions only; idempotent; warn-and-continue.
set -u
[ "${CLAUDE_CODE_REMOTE:-}" = "true" ] || exit 0
cd "${CLAUDE_PROJECT_DIR:-.}" || exit 0
warn() { printf 'session-start: %s\n' "$*" >&2; }

env_line() { # append an export line to the session env, once
  [ -n "${CLAUDE_ENV_FILE:-}" ] || return 0
  grep -qxF "$1" "$CLAUDE_ENV_FILE" 2>/dev/null || printf '%s\n' "$1" >>"$CLAUDE_ENV_FILE"
}

# --- Node from .node-version (VM nvm at /opt/nvm; image ships 20/21/22) ------
if [ -f .node-version ]; then
  pin="$(tr -d '[:space:]' <.node-version)"
  if [ "$(node --version 2>/dev/null)" != "v$pin" ]; then
    export NVM_DIR="${NVM_DIR:-/opt/nvm}"
    if [ -s "$NVM_DIR/nvm.sh" ]; then
      set +u
      . "$NVM_DIR/nvm.sh"
      nvm install "$pin" >/dev/null && nvm alias default "$pin" >/dev/null ||
        warn "Node $pin install failed; continuing on $(node --version 2>/dev/null || echo 'no node')"
      set -u
    else warn "nvm not found; Node $pin unavailable"; fi
  fi
  node_bin="$(dirname -- "$(command -v node)")"
  # shellcheck disable=SC2016
  env_line "export PATH=\"$node_bin:$PWD/node_modules/.bin:\$PATH\""
fi

# --- npm dependencies, skipped when already in sync --------------------------
if [ -f package-lock.json ]; then
  if [ ! -f node_modules/.package-lock.json ] ||
    [ package-lock.json -nt node_modules/.package-lock.json ]; then
    npm ci --no-audit --no-fund || warn "npm ci failed"
  fi
fi

# --- .NET SDK exactly as global.json pins, repo-local (.dotnet) --------------
if [ -f global.json ]; then
  sdk="$(jq -r '.sdk.version // empty' global.json 2>/dev/null)"
  if [ -n "$sdk" ]; then
    if [ ! -x .dotnet/dotnet ] || ! .dotnet/dotnet --list-sdks 2>/dev/null | grep -q "^$sdk "; then
      # Download-then-run: a curl failure piped into bash exits 0 and would mask the miss
      if ! curl -fsSL https://dot.net/v1/dotnet-install.sh -o /tmp/dotnet-install.sh ||
        ! bash /tmp/dotnet-install.sh --version "$sdk" --install-dir .dotnet; then
        warn "dotnet $sdk install failed"
      fi
    fi
    if [ -x .dotnet/dotnet ]; then
      env_line "export DOTNET_ROOT=\"$PWD/.dotnet\""
      # shellcheck disable=SC2016
      env_line "export PATH=\"$PWD/.dotnet:\$PATH\""
    fi
  fi
fi

# --- Python dependencies via uv ----------------------------------------------
if [ -f uv.lock ] && command -v uv >/dev/null; then
  uv sync || warn "uv sync failed"
fi

exit 0
```

Adoption order by payoff: **medley** (biggest repo, most sessions likely), **github-iac**,
**ci-workflows**, **standards**, **provisioning**, **claude-code-proxy**, then codex-plugins.
songwriting, knowledge-corpus, ci-runner, and the content repos need nothing.

## Step 3 — routines

Prereqs and constraints, then starters. Routines run as **fully autonomous** cloud sessions (no
permission prompts), belong to the account, draw down subscription usage, and have a daily run
cap. Two defaults deserve deliberate handling every time: **all connected connectors are
included by default — trim each routine to what it needs**, and GitHub triggers require the
Claude GitHub App installed on that repository (`/web-setup` alone grants clone access, not
webhooks). Create via `/schedule` in a local CLI session or at
[claude.ai/code/routines](https://claude.ai/code/routines); API triggers are web-only.

Starters matched to this fleet, cheapest first:

1. **Weekly upstream-drift re-verification** (this repo; schedule, weekly): re-fetch the pages
   behind `docs/OFFICIAL-DOCS.md` and `docs/CLOUD-SESSIONS.md` per the upstream-drift
   convention's fetch route, and open a PR when a stamp no longer matches. Connectors: none.
2. **Nightly backlog groom** (this repo; schedule, weeknights): triage new issues, label, link
   PRs per the repo's conventions. Connectors: none (built-in GitHub tools suffice).
3. **PR review on open** (medley; GitHub trigger `pull_request.opened`, filter `is draft:
   false`): apply the repo's review checklist as inline comments. Requires the GitHub App on
   medley.
4. **Standards-sync watchdog** (standards + consumers; schedule, daily): check
   `chore: sync standards components` PRs stuck unmerged and summarize. Connectors: none.

Write every routine prompt as a complete standalone instruction (each run is a fresh session with
no memory), and remember a green run status only means the session exited cleanly — read the
transcript to confirm the task itself succeeded.

## Verification checklist

Run once after creating the environment (and after any setup-script edit — each edit rebuilds
the cache). Executed live on 2026-08-14; results and forensics in
[#2654](https://github.com/melodic-software/claude-code-plugins/issues/2654). Start a cloud
session on this repo in the new environment and ask Claude to verify:

0. **The completion stamp first**: `cat /opt/melodic-env-setup.done` (version + timestamp). A
   missing stamp means the cache build was interrupted before the script finished — the exact
   #2654 Blocker 2 failure, where dpkg logs showed the build stopping ~13 s in with PowerShell
   and the baked-in bootstrap never run. Force a rebuild (any trivial script-field edit) before
   debugging anything else; `/var/log/melodic-env-setup.log` shows how far the build got.
1. `gh --version`, `pwsh --version`, `dotnet --list-sdks` (expect 10.0.302 and 10.0.400),
   `node --version` (expect the `.node-version` pin), `check-tools` for the VM inventory.
2. The repo's hook ran: `node_modules/.bin` populated, pinned lint tools present (`typos`,
   `actionlint`), and re-running the hook is a fast no-op.
3. `echo $GH_TOKEN` prints `proxy-injected` (GitHub proxy is authenticating).
4. Marketplace plugins loaded, in a session on a repo that declares them (songwriting or
   medley): make the session's *first* message a plugin slash command and confirm it resolves —
   `/plugin` is not available in cloud sessions, and a Bash-side
   `claude plugin list` proves only disk state, not that the session loaded anything (see the
   same-session limit in [CLOUD-SESSIONS.md](CLOUD-SESSIONS.md)).
5. If the .NET setup-script step failed (`dotnet` missing), confirm the environment actually has
   the Custom allowlist from [Step 1](#step-1--the-shared-environment-claudeai-ui-one-time) —
   under Trusted this step *always* fails (#2654 Blocker 1) — then rebuild and re-verify.
6. Python: in a claude-code-proxy or medley session, `uv python install 3.14` — if the download
   is `403`-blocked (release assets ride the GitHub proxy's repository scope), fall back to the
   VM's system Python for tooling or add the astral-sh host to a Custom allowlist. This repo's
   SessionStart hook installs from `.github/requirements-ci.txt` with `--require-hashes`; that
   pin list includes cp311 wheels so the cloud VM's system Python 3.11 can satisfy `pyyaml`
   (CI itself uses 3.14).

## Findings

- **Resolved: this repo's bootstrap was unwired; it is now registered.** The doc's original
  finding (committed `settings.json` carried neither the SessionStart hook nor `enabledPlugins`)
  was confirmed live by the 2026-08-14 verification run (#2654 check 2/4: empty
  `node_modules/.bin`, zero plugins). #2631 enabled the catalog; #2655 registered the SessionStart hook
  on a `startup|resume` matcher — and #2657 closed the last hook blocker (the
  `--require-hashes` pin list lacked cp311 wheels for the cloud VM's Python 3.11, so the hook
  failed deterministically; verified against PyPI's published digests, a coverage gap rather
  than tampering). A 2026-08-15 session then confirmed the wiring end to end — the hook ran at
  startup and installed all 65 plugins — and established the follow-on limit now recorded in
  `docs/CLOUD-SESSIONS.md` §"Plugins in sessions on this repo": hook-time installs land on disk
  but are never loaded by the session that ran them (the registry is read before the hook), so
  plugins go live at turn one only when the cache build runs the bootstrap pre-launch, which the
  standards `cloud-environment` component does. Remaining #2654 actions are environment-side,
  not repo-side: switch the environment to the Custom allowlist
  ([Step 1](#step-1--the-shared-environment-claudeai-ui-one-time)) and rebuild the interrupted
  cache, then re-run the [checklist](#verification-checklist).
- **`dotfiles` cannot deliver user config to the cloud.** By platform design nothing from
  `~/.claude` reaches cloud sessions; the repo remains editable in the cloud, but any behavior it
  installs locally must be re-homed (repo `.claude/`, plugins, or the environment) to exist
  there.
- **Windows-shaped work stays local.** `provisioning` runbooks and `dotfiles` Windows content
  can be authored and linted in cloud sessions (Ubuntu VMs) but never executed.
