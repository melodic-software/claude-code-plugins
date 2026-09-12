# Cloud fleet setup: one shared environment for every melodic-software repo

The goal-oriented companion to [cloud-sessions.md](cloud-sessions.md): that doc explains the
mechanics and this repo's own setup; this one gets **the whole fleet** runnable in Claude Code
cloud sessions (web, `claude --cloud`, mobile, desktop, and routines) with warm-boot startup.
Account context this plan is built for: a personal (Max) claude.ai account. Organization-shared
and self-hosted environments are Team/Enterprise features and deliberately out of scope.

Basis and freshness: the toolchain inventory below was derived from shallow clones of every
fleet repo's default branch on 2026-08-13; bootstrap adoption was re-verified on 2026-08-16 by
reading each repo's `.claude/` contents and `settings.json` at `origin/main` (`gh api
repos/melodic-software/<repo>/contents/.claude`); platform claims rest on the rung-1 doc fetches
recorded in [cloud-sessions.md](cloud-sessions.md); the environment itself was verified live on
2026-08-14 from a cloud session inside it. Results are in
[#2654](https://github.com/melodic-software/claude-code-plugins/issues/2654), folded in below.
Recheck trigger, per the [upstream-drift convention](conventions/upstream-drift/README.md): a
repo changes its toolchain pins (`global.json`, `.node-version`, `.python-version`, lockfiles)
or its `.claude/` config; or `melodic-software/standards`
`components/cloud-environment/setup.sh` changes (that file owns
`DOTNET_FALLBACK_VERSIONS` and `NODE_FALLBACK_VERSION`, the numbers copied into the
inventory below); or a verification session (see [checklist](#verification-checklist))
contradicts a claim here.

## The design in one paragraph

Cloud environments are account-scoped and repo-agnostic, and each environment's setup script
result is cached as a filesystem snapshot (the "warm boot": script runs once, later sessions boot
from the snapshot; rebuilds only on script/network edits or ~7-day expiry). So the fleet uses
**one shared environment** whose setup script installs the static toolchains the repos pin, inside
the ~5-minute cache-build budget: .NET SDK and Node at whatever the checked-out repo pins, with
fleet fallbacks for whichever of those two lanes the repo does not pin, plus `gh` and PowerShell.
Alongside it, **each repo carries its own bootstrap**: a committed, idempotent,
`CLAUDE_CODE_REMOTE`-guarded `.claude/cloud-bootstrap.sh` that installs manifest-driven
dependencies (`npm ci`, repo-local .NET, `uv sync`), run by the environment's setup script
pre-launch (the call that gets the repo's plugins loaded at turn one) and re-run per session by a
registered SessionStart hook as drift repair. Both halves stay generic. The script is one
canonical file distributed from standards,
and a repo's own steps live beside it in `.claude/cloud-bootstrap.local.sh`.

## Fleet toolchain inventory (2026-08-13)

The pins found across the fleet, the one input to
[Step 1](#step-1-the-shared-environment-claudeai-ui-one-time) that lives nowhere else. The .NET
and Node numbers below are fleet *fallbacks* owned by `DOTNET_FALLBACK_VERSIONS` and
`NODE_FALLBACK_VERSION` in standards `components/cloud-environment/setup.sh` (values as read
2026-09-08, and that script, not this list, is the source of truth); a checked-out repo
that pins a version in `global.json` or `.node-version` replaces that lane's fallback for the
cache build rather than adding to it, so a snapshot need not hold all of them at once.

Pinned toolchains found:

- **.NET SDK 10.0.302** (medley and github-iac, which set `rollForward: disable`, so the exact
  patch is required) and **10.0.400** (ci-workflows), the two fleet fallback SDKs.
- **Node 24.20.0**, the fleet fallback the setup script installs when the checked-out repo pins no
  `.node-version` (codex-plugins pins major 24). The cloud VM ships Node 20/21/22 only, so this
  is always an install.
- **Python 3.14** (medley, claude-code-proxy). The VM has `uv`. See the caveat below.
- **Go 1.26.6** (ci-runner). The VM's Go plus the module `toolchain` mechanism covers this.
- **PowerShell** (`pwsh`), not pre-installed. Six repos carry `PSScriptAnalyzerSettings.psd1`, and
  ci-workflows also runs Pester.

## Bootstrap adoption (2026-08-16)

Adoption is complete and no longer a per-repo decision surface: all fifteen non-archived
melodic-software repositories (`gh repo list melodic-software --json name,isArchived`) carry
`.claude/cloud-bootstrap.sh`, register it as a `startup|resume` SessionStart hook, and declare the
`melodic-software` marketplace. Enabling the catalog is not among the per-repo steps: the standards
fleet list does that for every repo, and a repo's own block carries only deltas
([Step 2](#step-2-per-repo-wiring)). Read adoption state from the repos rather than from a table
here; a per-repo enumeration in this doc can only lag them.

The script is owned upstream, not per repo: standards
[`components/cloud-bootstrap`](https://github.com/melodic-software/standards/blob/main/components/cloud-bootstrap/README.md)
is the canonical source and its README is the contract: what the generic script does, the
frozen calling contract with the environment, and the take / enrich / customize modes.
[`distribution/sync-manifest.yml`](https://github.com/melodic-software/standards/blob/main/distribution/sync-manifest.yml)
records which repositories take it `managed` (byte-exact materialization, so a fix lands once
and fans out as sync PRs) and which own their copy `locally-owned`; read the manifest rather
than a copy of it. Repo-specific steps go in a never-synced `.claude/cloud-bootstrap.local.sh`,
never in an edit to a materialized script.

Out of scope: the three archived repos, and `kyle-sexton/prereq-cancelled-verify` +
`kyle-sexton/autonomy-demo-scratch` (a session can attach repos from only one owner; audit those
from a session started on a `kyle-sexton` repo if they ever matter).

## Step 1: the shared environment (claude.ai UI, one time)

> **Rollout:** the paste kit for this step lives in
> [prompts/cloud-bootstrap-rollout.md](../prompts/cloud-bootstrap-rollout.md), and it supersedes
> any older advice to stand up a separate named Melodic environment. One environment per
> account, the **Default** one, edited in place. The committed bootstrap has one name
> (`.claude/cloud-bootstrap.sh`) and two callers: the environment's cache build pre-launch, and
> the SessionStart hook per session. The standards `cloud-environment` component invokes only
> that path, with no legacy fallback by decision, and pre-launch execution is what makes
> marketplace plugins load at turn one (see [cloud-sessions.md](cloud-sessions.md)).

Environments are created only from the environment selector at
[claude.ai/code](https://claude.ai/code) (cloud icon above the message box). There is no API.
Edit **Default** in place. The paste-once rollout settles on one account-wide Default rather
than a separate named environment (see
[One environment per account?](../prompts/cloud-bootstrap-rollout.md#one-environment-per-account)):

- **Network access**: **All**, by operator decision 2026-08-22, superseding this doc's earlier
  Custom allowlist (`dot.net`, `aka.ms`, `builds.dotnet.microsoft.com`,
  `download.visualstudio.microsoft.com`). The access level is an exfiltration control whose Custom
  default already opens publish-capable package registries; the GitHub proxy, MCP connector
  traffic and the Anthropic API bypass the level at every setting; and a blocked host mid-session
  kills the session until an environment edit plus a cache rebuild. **All** removes that failure
  class outright, the .NET case included: the 2026-08-14 verification run
  ([#2654](https://github.com/melodic-software/claude-code-plugins/issues/2654), Blocker 1)
  reproduced the .NET installer's redirect chain being `403`-blocked under *Trusted*, and that
  blocker is moot under All: no host list to keep current, and no narrower level left to choose
  between. The host list above is superseded history, not a recipe. The one exception that still
  needs a recipe: an account handling sensitive material drops back to **Custom**, and only a
  complete Custom is safe. That means **Also include default list of common package managers**
  checked, plus `dot.net`, `aka.ms`, `builds.dotnet.microsoft.com`, and
  `download.visualstudio.microsoft.com`; a Custom missing any of it leaves the .NET installer's
  redirect chain exposed to the same `403` block Blocker 1 demonstrated under Trusted.
- **Environment variables**: none. There is no secrets store. Anything here is readable by every
  session in the environment. `gh`/git auth comes from the GitHub proxy automatically.
- **Setup script**: paste only the three-line bootstrap below. The real script is the
  [`cloud-environment` component in standards](https://github.com/melodic-software/standards/blob/main/components/cloud-environment/setup.sh)
  (standards is the org baseline SSOT and is public, so the raw fetch needs no credentials and
  `raw.githubusercontent.com` is on the default allowlist). Edits to what environments install
  land there by reviewed PR, never by hand-editing this account-scoped UI field.

```bash
#!/bin/bash
curl -fsSL https://raw.githubusercontent.com/melodic-software/standards/main/components/cloud-environment/setup.sh \
  -o /tmp/melodic-env-setup.sh && bash /tmp/melodic-env-setup.sh
exit 0
```

What the canonical script does (details and lifecycle in the
[component README](https://github.com/melodic-software/standards/blob/main/components/cloud-environment/README.md)):
parallel tracks install `gh` (the pinned, checksum-verified `linux_amd64` release tarball from
`github.com/cli/cli`, at the same version and SHA-256 the CI runner image and dotfiles' mise pin
carry, because Ubuntu's archive `gh` is years stale) and PowerShell (apt), the .NET SDK into
`/opt/dotnet` and Node via the VM's nvm. When the checked-out repo pins a version in
`global.json` or `.node-version`, that pin replaces the matching fleet fallback for this
cache build rather than unioning with it, so a repo that pins one .NET SDK does not also
receive the other fallback SDK. The fleet pins cover whichever of those two the repo does
not pin. The env copy is still a warm cache: each repo's bootstrap installs its exact pins
repo-locally. The script then runs that repo's own `.claude/cloud-bootstrap.sh`, baking its
results into the snapshot; and then it fetches the standards fleet plugin list to
`/opt/melodic-fleet-plugins.json` and installs every `true` entry in it at user scope. That
plugin install is what makes the fleet's plugins live at turn one, because it runs before
the session process launches and the plugin registry is read at process start. Every step logs with a timestamp to
`/var/log/melodic-env-setup.log`, and `/opt/melodic-env-setup.done` (version + timestamp) is
written strictly last, so a missing stamp is the signature of an interrupted cache build
([#2654](https://github.com/melodic-software/claude-code-plugins/issues/2654) Blocker 2), fixed
by forcing a rebuild.

Two lifecycle caveats: the fleet's toolchain pins are duplicated into the component by necessity
(the script cannot read repos it isn't running in). Each repo's bootstrap *also* installs its
exact SDK repo-locally, so the env copy is a warm cache and the bootstrap is the correctness
guarantee. And
a merged component change does **not** reach existing environments on its own: the snapshot
rebuilds only on an edit to the environment's script/network fields or ~7-day cache expiry, so
after a standards bump, force a rebuild with any trivial edit to the script field.

## Step 2: per-repo wiring

Two committed files per repo, so every cloud session picks them up from the clone; nothing
depends on `~/.claude`.

**`.claude/settings.json`**: register the hook (merge into the existing file where one exists),
and declare the marketplace the way medley and songwriting already do (`github` source, which
resolves in cloud sessions, unlike anything user-scoped):

```json
{
  "hooks": {
    "SessionStart": [
      {
        "matcher": "startup|resume",
        "hooks": [
          {
            "type": "command",
            "command": "bash \"$CLAUDE_PROJECT_DIR\"/.claude/cloud-bootstrap.sh"
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
  "enabledPlugins": { "<plugin-to-opt-out>@melodic-software": false }
}
```

The fleet's plugin set is not declared per repo: the shared environment installs the standards
fleet list
([`components/cloud-environment/fleet-plugins.json`](https://github.com/melodic-software/standards/blob/main/components/cloud-environment/fleet-plugins.json))
into every snapshot, and the bootstrap reads that list overlaid with the repo's own block. So a
repo's `enabledPlugins` carries only deltas: an explicit `false` to opt out of a fleet entry, or
a `true` for a plugin beyond the fleet. The overlay is settings-wins: where both files name the
same plugin the repo's value takes precedence, which is what makes the `false` an opt-out. A
block that mirrors the whole catalog still works, since a repeated `true` agrees with the fleet
entry it overrides, but writes one project-scope install record per entry per checkout
on every local session start, which is the accumulation #3688 removed.

**`.claude/cloud-bootstrap.sh`**: do not author one. The canonical script is generic and
manifest-driven (it carries no repo names, no marketplace identifiers, and no pinned versions),
and it lives in standards
[`components/cloud-bootstrap`](https://github.com/melodic-software/standards/blob/main/components/cloud-bootstrap/README.md);
that README is the contract, and the
[sync manifest](https://github.com/melodic-software/standards/blob/main/distribution/sync-manifest.yml)
decides whether a repo takes it `managed` or owns it `locally-owned`. The script has exactly one
copy; this doc does not carry a second one. A repo onboarding before its manifest row lands
copies the component file verbatim as an interim `.claude/cloud-bootstrap.sh` and proposes the
row; the sync replaces the copy byte-exact when the row merges.

Repo-specific steps go in a committed `.claude/cloud-bootstrap.local.sh`: extra lockfile
locations, pinned hygiene binaries, symlinks. The canonical script runs that file after its
generic toolchain stage, and it is never synced and never overwritten. Same contract as its
caller: cloud-only, idempotent, best effort, bash-3.2-safe, always exit 0. That extension point
is a canonical-script feature: it is live wherever the synced script is (the `managed` targets),
and a `locally-owned` repo, this one included, owns its whole file instead, so it has no
`cloud-bootstrap.local.sh` and needs none.

## Step 3: routines

Prereqs and constraints, then starters. Routines run as **fully autonomous** cloud sessions (no
permission prompts), belong to the account, draw down subscription usage, and have a daily run
cap. Two defaults deserve deliberate handling every time: **all connected connectors are
included by default, so trim each routine to what it needs**, and GitHub triggers require the
Claude GitHub App installed on that repository (`/web-setup` alone grants clone access, not
webhooks). Create via `/schedule` in a local CLI session or at
[claude.ai/code/routines](https://claude.ai/code/routines); API triggers are web-only.

Starters matched to this fleet, cheapest first:

1. **Weekly upstream-drift re-verification** (this repo; schedule, weekly): re-fetch the pages
   behind `docs/official-docs.md` and `docs/cloud-sessions.md` per the upstream-drift
   convention's fetch route, and open a PR when a stamp no longer matches. Connectors: none.
2. **Nightly backlog groom** (this repo; schedule, weeknights): triage new issues, label, link
   PRs per the repo's conventions. Connectors: none (built-in GitHub tools suffice).
3. **PR review on open** (medley; GitHub trigger `pull_request.opened`, filter `is draft:
   false`): apply the repo's review checklist as inline comments. Requires the GitHub App on
   medley.
4. **Standards-sync watchdog** (standards + consumers; schedule, daily): check
   `chore: sync standards components` PRs stuck unmerged and summarize. Connectors: none.

Write every routine prompt as a complete standalone instruction (each run is a fresh session with
no memory), and remember a green run status only means the session exited cleanly. Read the
transcript to confirm the task itself succeeded.

## Verification checklist

Run once after creating the environment (and after any setup-script edit, since each edit
rebuilds the cache). Executed live on 2026-08-14; results and forensics in
[#2654](https://github.com/melodic-software/claude-code-plugins/issues/2654). Start a cloud
session on this repo in the new environment and ask Claude to verify:

0. **The completion stamp first**: `cat /opt/melodic-env-setup.done` (version + timestamp). A
   missing stamp means the cache build was interrupted before the script finished, the exact
   #2654 Blocker 2 failure, where dpkg logs showed the build stopping ~13 s in with PowerShell
   and the baked-in bootstrap never run. Force a rebuild (any trivial script-field edit) before
   debugging anything else; `/var/log/melodic-env-setup.log` shows how far the build got.
1. `gh --version`: read the number, don't just confirm the binary exists. Expect **2.98.0 or
   newer**, the version the CI runner image and dotfiles' mise pin both carry. A `2.45.x` here
   has two possible causes, and step 0's completion stamp tells them apart before you dig
   further: if the stamp predates this pin (check its timestamp against when the pinned-tarball
   change landed in `components/cloud-environment/setup.sh`), the session simply cached an
   older script version. Force a rebuild (any trivial script-field edit) rather than treating
   this as a failure. Only once the stamp is current does a `2.45.x` reading mean the setup
   script's pinned-tarball step actually failed (`grep gh /var/log/melodic-env-setup.log` for
   its `WARN`), leaving scripts that shell out to `gh` running against a CLI 53 minor versions
   behind the other two lanes.
   Then `pwsh --version`, `dotnet --list-sdks` (expect the repo's `global.json` pin, or the SDKs
   `DOTNET_FALLBACK_VERSIONS` lists when the repo declares none, as this repo does), `node
   --version` (expect the `.node-version` pin, or `NODE_FALLBACK_VERSION` when the repo declares
   none). Read both variables from standards `components/cloud-environment/setup.sh` at check
   time rather than expecting the numbers recorded above. Then `check-tools` for the VM
   inventory.
2. The repo's bootstrap ran: `node_modules/.bin` populated, pinned lint tools present (`typos`,
   `actionlint`), and re-running the bootstrap is a fast no-op.
3. `echo $GH_TOKEN` prints `proxy-injected` (GitHub proxy is authenticating).
4. Marketplace plugins loaded, in a session on a repo that declares them (songwriting or
   medley): make the session's *first* message a plugin slash command and confirm it resolves.
   `/plugin` is not available in cloud sessions, and a Bash-side
   `claude plugin list` proves only disk state, not that the session loaded anything (see the
   same-session limit in [cloud-sessions.md](cloud-sessions.md)).
5. If the .NET setup-script step failed (`dotnet` missing), confirm the environment's network
   access is **All** per [Step 1](#step-1-the-shared-environment-claudeai-ui-one-time), since a
   narrower level can `403`-block the installer's redirect chain (#2654 Blocker 1), which All
   moots. Then rebuild and re-verify. If it is already All, the cause is not network access:
   read `/var/log/melodic-env-setup.log` for what the .NET track actually hit.
6. Python: in a claude-code-proxy or medley session, run `uv python install 3.14`. If the
   download is `403`-blocked (release assets ride the GitHub proxy's repository scope, which
   applies at every network access level), fall back to the VM's system Python for tooling. This repo's
   cloud bootstrap installs from `.github/requirements-ci.txt` with `--require-hashes`; that
   pin list includes cp311 wheels so the cloud VM's system Python 3.11 can satisfy `pyyaml`
   (CI itself uses 3.14).

## Findings

- **Resolved: this repo's bootstrap was unwired; it is now registered.** The doc's original
  finding (committed `settings.json` carried neither the SessionStart hook nor `enabledPlugins`)
  was confirmed live by the 2026-08-14 verification run (#2654 check 2/4: empty
  `node_modules/.bin`, zero plugins). #2631 enabled the catalog; #2655 registered the SessionStart hook
  on a `startup|resume` matcher, and #2657 closed the last hook blocker (the
  `--require-hashes` pin list lacked cp311 wheels for the cloud VM's Python 3.11, so the hook
  failed deterministically; verified against PyPI's published digests, a coverage gap rather
  than tampering). A 2026-08-15 session then confirmed the wiring end to end, with the hook
  running at startup and installing all 65 plugins, and established the follow-on limit now recorded in
  `docs/cloud-sessions.md` §"Plugins in sessions on this repo": hook-time installs land on disk
  but are never loaded by the session that ran them (the registry is read before the hook), so
  plugins go live at turn one only when the cache build runs the bootstrap pre-launch, which the
  standards `cloud-environment` component does. Remaining #2654 actions are environment-side,
  not repo-side: set the environment's network access to **All**
  ([Step 1](#step-1-the-shared-environment-claudeai-ui-one-time)), which moots Blocker 1 rather
  than working around it, and rebuild the interrupted cache, then re-run the
  [checklist](#verification-checklist).
- **`dotfiles` cannot deliver user config to the cloud.** By platform design nothing from
  `~/.claude` reaches cloud sessions; the repo remains editable in the cloud, but any behavior it
  installs locally must be re-homed (repo `.claude/`, plugins, or the environment) to exist
  there.
- **Windows-shaped work stays local.** `provisioning` runbooks and `dotfiles` Windows content
  can be authored and linted in cloud sessions (Ubuntu VMs) but never executed.
