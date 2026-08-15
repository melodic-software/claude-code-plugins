# Cloud bootstrap rollout — paste kit

Copy-paste material for rolling the fleet onto the split cloud-bootstrap layout: the canonical
setup-script stub pasted once per claude.ai account, shared provisioning in the public
`melodic-software/standards` repo's
[`cloud-environment` component](https://github.com/melodic-software/standards/blob/main/components/cloud-environment/setup.sh),
and a mechanical per-repo migration prompt. Mechanics and evidence live in
[docs/CLOUD-SESSIONS.md](../docs/CLOUD-SESSIONS.md) §"Plugins in sessions on this repo"; the
fleet inventory and the canonical stub's home live in
[docs/CLOUD-FLEET-SETUP.md](../docs/CLOUD-FLEET-SETUP.md).

## Why this layout (verified 2026-08-15)

- Claude Code builds its plugin/command/skill registry at **process start** and never re-reads
  it. A SessionStart hook's `claude plugin install` calls land on disk but are invisible to the
  session that ran them; they load on the *next* process start (a resume, or a fresh session
  whose environment cache pre-installed them at build time).
- The environment **setup script** runs after the repo is cloned and before the Claude process
  starts — the only slot where provisioning precedes registry load. The standards
  `cloud-environment` component (which the stub fetches) runs the checked-out repo's committed
  bootstrap there; the repo's SessionStart hook runs the *same* script per session as drift
  repair. A file named and homed as "a SessionStart hook" is the wrong semantics for that shared
  role — hence the rename to `.claude/cloud-bootstrap.sh` with two thin callers.
- Environments are account-scoped with **no API**, so every setup-script edit is manual clicking
  multiplied by every account. The pasted stub therefore stays minimal and stable; everything
  that evolves lands in standards or in each repo by reviewed PR.

Ordering: do Part 1 (standards) before Part 2 (accounts) — an account cache built before the
component change lands simply misses it until its next rebuild, because publishing a component
change does **not** invalidate already-built caches; only a script/network edit in the account
UI or ~7-day expiry does.

## Part 1 — standards repo, once (paste into a session on `melodic-software/standards`)

```text
Update the existing Claude Code cloud-environment component in this repo
(components/cloud-environment/setup.sh and its README) for the fleet's
bootstrap-rename rollout.

Context (verified 2026-08-15 in melodic-software/claude-code-plugins — see its
docs/CLOUD-SESSIONS.md §"Plugins in sessions on this repo" and
docs/CLOUD-FLEET-SETUP.md): Claude Code builds its plugin/command/skill
registry at process start and never re-reads it, so plugin installs must land
before the session process launches — i.e. in this component at environment
cache build — to be loaded at turn one. Fleet repos are renaming their
committed bootstrap from .claude/hooks/session-start.sh to
.claude/cloud-bootstrap.sh (one script, two callers: this component
pre-launch, and the repo's SessionStart hook per session).

Do this:
1. Where the component runs the checked-out repo's bootstrap, invoke
   .claude/cloud-bootstrap.sh when present — and only that path, no
   session-start.sh fallback — best-effort (|| true) with
   CLAUDE_CODE_REMOTE=true and with CLAUDE_PROJECT_DIR set to the checkout
   root, so repo scripts never have to guess their root from their own path.
   A repo without the file is a clean no-op: it simply has not migrated yet,
   and its sessions rely on their SessionStart hook until it does.
2. Update the component README (division of labor, account stub if it is
   reproduced there) to match, and restate the rebuild rule: a merged
   component change reaches an environment only on its next cache rebuild —
   a trivial edit to the account's script field forces one.
3. shellcheck the script, keep every step best-effort and exit-0 within the
   ~5-minute cache-build budget, then commit (Conventional Commits) and
   push / open a PR per this repo's conventions.

Report the diff summary and anything you could not verify from this session.
```

## Part 2 — per account, once (~2 minutes each)

For each claude.ai account, at [claude.ai/code](https://claude.ai/code) → environment selector →
edit **Default** (one environment per account; see the rationale at the end):

1. **Network access**: **Custom**, with **Also include default list of common package managers**
   checked, plus these hosts: `dot.net`, `aka.ms`, `builds.dotnet.microsoft.com`,
   `download.visualstudio.microsoft.com`. Not optional if the fleet keeps .NET in the
   environment: under Trusted the .NET install *always* fails
   ([#2654](https://github.com/melodic-software/claude-code-plugins/issues/2654) Blocker 1).
2. **Environment variables**: none (values are readable by every session; there is no secrets
   store).
3. **Setup script**: paste the canonical stub below (same as
   [CLOUD-FLEET-SETUP.md](../docs/CLOUD-FLEET-SETUP.md) step 1), save. Saving rebuilds the
   environment cache, which is also how a later standards component change is picked up early —
   any trivial edit-and-save forces a rebuild.

   ```bash
   #!/bin/bash
   curl -fsSL https://raw.githubusercontent.com/melodic-software/standards/main/components/cloud-environment/setup.sh \
     -o /tmp/melodic-env-setup.sh && bash /tmp/melodic-env-setup.sh
   exit 0
   ```

4. **Verify**: start a fresh session on a repo that declares plugins and make the *first*
   message a plugin slash command (e.g. `/claude-config:audit` on claude-code-plugins). If it
   resolves, pre-launch install works end to end. If not: `/opt/melodic-env-setup.done` missing
   means an interrupted cache build (#2654 Blocker 2 — force a rebuild);
   `/var/log/melodic-env-setup.log` shows what the build did; and a populated
   `~/.claude/plugins/installed_plugins.json` alongside an unloaded catalog means the snapshot's
   `~/.claude` did not reach the session — a platform limitation to report upstream (resume is
   the standing workaround).

## Part 3 — every repo (the copy-paste migration prompt)

```text
Migrate this repository's Claude Code cloud bootstrap from the SessionStart-hook
layout to the split cloud-bootstrap layout.

Context (verified 2026-08-15 in melodic-software/claude-code-plugins, see its
docs/CLOUD-SESSIONS.md §"Plugins in sessions on this repo"): Claude Code builds
its plugin/command/skill registry at process start and never re-reads it, so
anything a SessionStart hook installs is invisible to the session that ran the
hook. Our account environments fetch the standards cloud-environment component
at cache build; after cloning, it runs the repo's committed
.claude/cloud-bootstrap.sh (that exact path only — no session-start.sh
fallback) with CLAUDE_CODE_REMOTE=true BEFORE the session process launches —
that pre-launch call is what makes plugins live at turn one, so this migration
is what switches it on for this repo. The SessionStart hook stays registered
and runs the same script per
session start/resume as drift repair (the environment cache can be ~7 days
stale); its plugin installs go live at the next resume.

Do this:
1. If .claude/hooks/session-start.sh exists, git mv it to
   .claude/cloud-bootstrap.sh. If the repo has no cloud bootstrap script at
   all, stop and report that instead of inventing one.
2. Keep the script's CLAUDE_CODE_REMOTE guard, idempotency, and provisioning
   logic intact — but audit any path-relative self-location: a fallback that
   derives the repo root from the script's own path (e.g.
   "$(dirname "${BASH_SOURCE[0]}")/../.." from the old .claude/hooks/ depth)
   now resolves one level too high. Adjust it to the new .claude/ depth
   ("$(dirname "${BASH_SOURCE[0]}")/..") and keep CLAUDE_PROJECT_DIR as the
   preferred source of the root.
3. Rewrite header comments that describe it as "a SessionStart hook": it is
   the repo's cloud bootstrap with two callers — the environment cache build
   pre-launch (the only path that gets plugins loaded at turn one) and the
   SessionStart hook (per-session drift repair).
4. In .claude/settings.json, point the SessionStart hook (matcher
   startup|resume) at:
   bash "$CLAUDE_PROJECT_DIR/.claude/cloud-bootstrap.sh"
   Leave all other hooks and settings untouched.
5. Search the repo for remaining references to session-start.sh (docs, CI,
   scripts) and update them.
6. Verify: bash -n on the script; shellcheck if available; in this cloud
   session run it twice with CLAUDE_CODE_REMOTE=true and confirm the second
   run is a fast no-op and that it operated on the repo root (not its
   parent); run it once without the variable and confirm it exits immediately
   without mutating anything.
7. Commit with a Conventional Commits message, e.g.
   refactor(claude): split cloud bootstrap out of the SessionStart hook
   and push / open a PR per this repository's contribution conventions.

Report: what moved, the new hook registration, any references you could not
fix, and the verification results.
```

## One environment per account?

Yes. Environments are account-scoped and repo-agnostic, the stub is generic (all real work is
delegated to the standards component and the checked-out repo's own script), and with 10–20
accounts every extra environment multiplies manual UI work. Edit **Default** in place — with the
Custom network allowlist from Part 2, which every account needs anyway — rather than adding a
named environment; add a second environment later only when a class of work needs isolation (a
different domain allowlist, or an SDK heavy enough that its cache churn should be contained).
This supersedes the "add a *Melodic* environment so Default stays pristine" option in
[docs/CLOUD-FLEET-SETUP.md](../docs/CLOUD-FLEET-SETUP.md) for the paste-once fleet play.
