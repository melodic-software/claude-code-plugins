# Cloud bootstrap rollout — paste kit

Copy-paste material for rolling the fleet onto the split cloud-bootstrap layout: one tiny
setup-script stub pasted once per claude.ai account, shared provisioning hosted in the public
`melodic-software/standards` repo, and a mechanical per-repo migration prompt. Mechanics and
evidence live in [docs/CLOUD-SESSIONS.md](../docs/CLOUD-SESSIONS.md) §"Plugins in sessions on
this repo"; the fleet inventory lives in
[docs/CLOUD-FLEET-SETUP.md](../docs/CLOUD-FLEET-SETUP.md).

## Why this layout (verified 2026-08-15)

- Claude Code builds its plugin/command/skill registry at **process start** and never re-reads
  it. A SessionStart hook's `claude plugin install` calls land on disk but are invisible to the
  session that ran them; they load on the *next* process start (a resume, or a fresh session
  whose environment setup script pre-installed them at cache build).
- The environment **setup script** runs after the repo is cloned and before the Claude process
  starts — the only slot where provisioning precedes registry load. So the same bootstrap must
  be callable from the setup script (pre-launch, makes plugins live at turn one) and from the
  SessionStart hook (per-session drift repair, live after the next resume). A file named and
  homed as "a SessionStart hook" is the wrong semantics for that shared role — hence
  `.claude/cloud-bootstrap.sh` with two thin callers.
- Environments are account-scoped with **no API**, so every setup-script edit is manual clicking
  multiplied by every account. The pasted stub therefore stays minimal and stable; everything
  that evolves lives in the public standards repo and in each repo's committed bootstrap.

## Part 1 — per account, once (~2 minutes each)

For each claude.ai account, at [claude.ai/code](https://claude.ai/code) → environment selector →
edit **Default** (one environment per account; see the rationale at the end):

1. **Network access**: Trusted.
2. **Environment variables**: none (values are readable by every session; there is no secrets
   store).
3. **Setup script**: paste the stub below, save. Saving rebuilds the environment cache.

   ```bash
   #!/bin/bash
   # Melodic cloud environment stub — paste once per account and leave alone.
   # Everything that can change lives in melodic-software/standards (shared,
   # repo-agnostic toolchain) and in each repo's committed .claude/cloud-bootstrap.sh
   # (repo-specific provisioning, incl. plugin installs, which must land here —
   # before the session process starts — to be loaded at turn one).
   curl -fsSL https://raw.githubusercontent.com/melodic-software/standards/main/cloud/env-setup.sh | bash || true
   if [ -f .claude/cloud-bootstrap.sh ]; then
     CLAUDE_CODE_REMOTE=true bash .claude/cloud-bootstrap.sh || true
   elif [ -f .claude/hooks/session-start.sh ]; then # repo not migrated yet
     CLAUDE_CODE_REMOTE=true bash .claude/hooks/session-start.sh || true
   fi
   exit 0
   ```

4. **Verify**: start a fresh session on a repo that declares plugins and make the *first*
   message a plugin slash command (e.g. `/claude-config:audit` here). If it resolves, the
   pre-launch install works end to end. If it does not, check whether
   `raw.githubusercontent.com` was reachable at cache build (`curl` it from the session) and
   whether `~/.claude/plugins/installed_plugins.json` is populated at session start — an
   installed-but-unloaded state means the snapshot's `~/.claude` did not reach the session,
   which is a platform limitation to report upstream.

## Part 2 — standards repo, once (paste into a session on `melodic-software/standards`)

```text
Create the shared Claude Code cloud-environment setup script this org's account
environments fetch at cache build, plus its docs.

Context (verified 2026-08-15 in melodic-software/claude-code-plugins, see its
docs/CLOUD-SESSIONS.md): Claude Code cloud environments are account-scoped with
no API, so each account's environment setup script is a tiny pasted stub that
fetches this repo's script via
https://raw.githubusercontent.com/melodic-software/standards/main/cloud/env-setup.sh
and then runs the checked-out repo's .claude/cloud-bootstrap.sh when present.
This repo must therefore host the repo-agnostic half.

Do this:
1. Create cloud/env-setup.sh: the repo-agnostic union toolchain for the fleet,
   seeded from the Step-1 script in claude-code-plugins
   docs/CLOUD-FLEET-SETUP.md — apt gh + PowerShell, .NET SDKs 10.0.302 and
   10.0.400 via dot.net/v1/dotnet-install.sh into /opt/dotnet, Node 24.18.0 via
   the VM's nvm — parallel tracks, every step best-effort (|| true), must exit
   0, total runtime well under the ~5-minute environment cache-build budget.
   This repo is public, so nothing secret may ever go in it.
2. Create cloud/README.md documenting: the account stub (copy it verbatim from
   claude-code-plugins prompts/cloud-bootstrap-rollout.md Part 1), the division
   of labor (stub → this script → per-repo .claude/cloud-bootstrap.sh), the
   pin-vs-main tradeoff (the stub fetches main so behavior evolves without
   touching accounts; pin a tag in the stub instead if supply-chain posture
   ever outweighs that), and the update rule: editing env-setup.sh changes
   every account's next cache rebuild, so keep it repo-agnostic and best-effort.
3. shellcheck cloud/env-setup.sh, run it twice in this cloud session to prove
   idempotency, then commit (Conventional Commits) and push per this repo's
   conventions.
Report what you created and the raw URL the stub should fetch.
```

## Part 3 — every other repo (the copy-paste migration prompt)

```text
Migrate this repository's Claude Code cloud bootstrap from the SessionStart-hook
layout to the split cloud-bootstrap layout.

Context (verified 2026-08-15 in melodic-software/claude-code-plugins, see its
docs/CLOUD-SESSIONS.md §"Plugins in sessions on this repo"): Claude Code builds
its plugin/command/skill registry at process start and never re-reads it, so
anything a SessionStart hook installs is invisible to the session that ran the
hook. Our account environments' setup scripts therefore run the repo's
committed .claude/cloud-bootstrap.sh (with CLAUDE_CODE_REMOTE=true) after clone
and BEFORE the session process launches — that pre-launch call is what makes
plugins live at turn one. The SessionStart hook stays registered and runs the
same script per session start/resume as drift repair (the environment cache can
be ~7 days stale); its plugin installs go live at the next resume.

Do this:
1. If .claude/hooks/session-start.sh exists, git mv it to
   .claude/cloud-bootstrap.sh. If the repo has no cloud bootstrap script at
   all, stop and report that instead of inventing one.
2. Keep the script's CLAUDE_CODE_REMOTE guard, idempotency, and provisioning
   logic intact. Rewrite header comments that describe it as "a SessionStart
   hook": it is the repo's cloud bootstrap with two callers — the environment
   setup script (pre-launch; the only path that gets plugins loaded at turn
   one) and the SessionStart hook (per-session drift repair).
3. In .claude/settings.json, point the SessionStart hook (matcher
   startup|resume) at:
   bash "$CLAUDE_PROJECT_DIR/.claude/cloud-bootstrap.sh"
   Leave all other hooks and settings untouched.
4. Search the repo for remaining references to session-start.sh (docs, CI,
   scripts) and update them.
5. Verify: bash -n on the script; shellcheck if available; in this cloud
   session run it twice with CLAUDE_CODE_REMOTE=true and confirm the second
   run is a fast no-op; run it once without the variable and confirm it exits
   immediately without mutating anything.
6. Commit with a Conventional Commits message, e.g.
   refactor(claude): split cloud bootstrap out of the SessionStart hook
   and push / open a PR per this repository's contribution conventions.

Report: what moved, the new hook registration, any references you could not
fix, and the verification results.
```

## One environment per account?

Yes. Environments are account-scoped and repo-agnostic, the stub is generic (all real work is
delegated to the fetched script and the checked-out repo), and with 10–20 accounts every extra
environment multiplies manual UI work. Edit **Default** in place rather than adding a named
environment; add a second environment later only when a class of work needs isolation — a
custom domain allowlist, or an SDK heavy enough that its cache churn should be contained. This
supersedes the "add a *Melodic* environment so Default stays pristine" option in
[docs/CLOUD-FLEET-SETUP.md](../docs/CLOUD-FLEET-SETUP.md) for the paste-once fleet play.
