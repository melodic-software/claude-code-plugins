---
name: setup
description: "Verify the guardrails hooks' runtime prerequisites and per-guard toggle state for this machine. Use when: 'set up guardrails', 'configure guardrails', 'is guardrails working', 'which guards are on', a guard failed open with a jq notice, after tuning guard toggles, or 'install the commit-msg hook' / 'enforce the commit convention for every committer'. Actions: check (read-only verification, default) | apply (resolve what check found) | apply install-commit-msg (opt-in: install the tool-agnostic commit-msg convention hook into this repo's personal .git/hooks). Re-runnable and safe."
argument-hint: "check | apply | apply install-commit-msg"
user-invocable: true
disable-model-invocation: true
---

## Purpose

Thin check-centric setup per the uniform contract: `check` inspects and reports, `apply`
resolves. This plugin owns no consumer-project configuration — every tunable is a native
`userConfig` option (eight per-guard toggles plus the `cli_flag_verify_bins`,
`cli_flag_verify_skip_bins`, and `block_dangerous_git_allow` scalars) — so `apply` is pure
guidance and writes nothing.

Action routing: no argument or `check` runs the check; `apply` runs the check first, then
points at each remediation. Both are non-interactive — never prompt when the action is given.

## `check` (read-only)

The guard scripts (`${CLAUDE_PLUGIN_ROOT}/hooks/*.sh`) and `hooks.json` are the single
source of truth for the guard inventory and each guard's runtime needs. **Read them
first** — probe what they actually require, don't recite this file. Then run each probe
via Bash and report a PASS/FAIL/INFO table with one remediation line per FAIL.

When every guard's toggle is disabled, prerequisite absences downgrade from FAIL to INFO —
a deliberately disabled plugin is not broken. Report the probes informationally and note
that re-enabling restores the FAIL semantics.

1. **Bash 5.0+** — the guards' documented runtime floor (Git Bash on native Windows).
   FAIL below the floor with the README Requirements remediation.
2. **`jq`** — `command -v jq`. FAIL if absent: per the README, every guard then fails
   OPEN (disabled) with a one-line stderr notice — the machine is unguarded, which is
   exactly what this check exists to surface.
3. **Per-guard toggles** — report each guard's effective value from its
   `${user_config.<guard>_enabled}` rendering (unexpanded or empty means default `true`),
   one row per guard, so the user sees the live guard surface at a glance.
4. **`cli-flag-verify` scan surface** — report the effective `cli_flag_verify_bins` /
   `cli_flag_verify_skip_bins` values and INFO-note the guard's own behavior for scanned
   binaries missing from `PATH` (skipped, never flagged — per the guard source).
5. **`block-dangerous-git` allowlist** — report the effective `block_dangerous_git_allow`
   value (patterns only, verbatim; it contains no secrets by design).
6. **Hook registration** — INFO: confirm the plugin is enabled for this project
   (`/plugin` → Installed) rather than parsing settings files.

## `apply` (idempotent)

Run `check`, then for each FAIL point at the resolution. Every prerequisite is a system
tool and every tunable is native `userConfig`, so `apply` installs nothing and writes
nothing — it only points:

- missing `jq` / old Bash: platform install instructions from the README Requirements
  section; this skill never installs system packages.
- any toggle or scalar change: direct to `/plugin configure guardrails` (interactive, any
  time). Headless: `--config` only applies on a fresh install (ignored once installed), so
  reconfigure via `claude plugin uninstall guardrails -s <scope>` then
  `claude plugin install guardrails@<marketplace> -s <scope> --config KEY=VALUE …` (repeatable);
  this skill never writes user settings or `pluginConfigs`. Both commands default to `-s user` —
  pass the scope `claude plugin list` reports for this plugin, and run from that project's
  directory for a `project`/`local` scope. Defaulting instead uninstalls a separate user-scope
  record while the effective install stays in place, so the reinstall lands at a scope that
  does not load.

Re-running `apply` after everything passes changes nothing and reports "already configured".

## `apply install-commit-msg` (opt-in, explicit argument only)

The DEPTH layer of commit-convention enforcement: a git `commit-msg` hook validating every
commit on this machine in this repo — editor commits, `git commit -F <file>`, IDE
integrations, humans outside Claude — against the same team-tracked pattern the CC-layer
`block-convention-violation` guard reads, through a copy of the same resolver. Never runs
from bare `apply`; only the explicit `install-commit-msg` argument installs anything.

**Lane: personal `.git/hooks/` only.** This writes the CURRENT OPERATOR's repo-local hooks
directory — invisible to teammates, uncommitted, removable by deleting two files. A
committed team lane (`core.hooksPath` pointing at a tracked directory) is deliberately NOT
scaffolded: `core.hooksPath` changes are exactly what the `block-no-verify` guard refuses
as a hook-bypass shape, and pointing every teammate's git at a tracked hooks dir is a team
decision made by a human in a PR, not by this skill. When the team wants shared
enforcement, say so and point at a commit-msg entry in the repo's own hook manager
(lefthook/husky/CI) instead.

**Preflight — refuse rather than surprise (run all, report, stop on any REFUSE):**

1. **Managed-repo detection.** `git config --get core.hooksPath` non-empty, or
   `lefthook.yml`/`.lefthook.yml`, `.husky/`, or a `pre-commit` config managing hooks →
   REFUSE: the repo's hook manager owns this surface; installing behind its back invites
   silent shadowing. Remediation: add the convention check to the manager's own
   `commit-msg` entry.
2. **Existing `commit-msg` hook.** Present and NOT sentinel-marked → offer exactly two
   paths and default to refusing: **chain** (rename the existing hook to
   `commit-msg.pre-guardrails`; the installed hook runs it first and its rejection is
   final) or **refuse** (leave everything untouched). Never overwrite. This includes an
   operator's machine-local commit-msg gate — chaining preserves it.
3. **Sentinel-marked hook already installed** → idempotent re-install: overwrite the two
   guardrails-owned files in place (template may have updated), report "refreshed".

**Install (on a clean preflight):** copy `${CLAUDE_PLUGIN_ROOT}/lib/git-hooks/commit-msg-convention.sh`
to `<git-dir>/hooks/commit-msg` and `${CLAUDE_PLUGIN_ROOT}/hooks/resolve-convention-pattern.sh`
to `<git-dir>/hooks/guardrails-resolve-convention.sh` (resolve `<git-dir>` via
`git rev-parse --absolute-git-dir` — in a worktree `.git` is a file), `chmod +x` both.

**Verify + report:** run the installed hook against a throwaway conforming and violating
message file and show both outcomes; state the removal path (delete the two files; restore
`commit-msg.pre-guardrails` to `commit-msg` if chaining renamed one) and that
**unresolved = no enforcement** — with no team-tracked `subject_pattern` the hook
passes everything, so installing before `/source-control:setup apply` writes a convention
is inert, not harmful.

**Known interactions (state them in the report):**

- `--no-verify` skips commit-msg hooks, and the guardrails `block-no-verify` guard blocks
  that flag in Claude sessions — by design the only exit from a rejection is a compliant
  subject (the hook's message says exactly that and never suggests bypass).
- The CC-layer `block-convention-violation` guard usually blocks a violating subject
  before git ever runs, so this hook firing in a Claude session means the CC layer was
  bypassed or disabled — it is the backstop, not the primary UX.
- Convention-inference tooling must skip sentinel-marked hooks (the
  `guardrails-commit-msg-convention` marker) — the hook is derived FROM the tracked
  config and is not an independent convention signal.

## What this skill does NOT do

- Exercise a guard — any matching tool call does that end-to-end.
- Write the plugin cache, Claude Code user settings, or `pluginConfigs`.
- Install any tool, during either `check` or `apply` — guidance only. The ONLY write this
  skill ever performs is the explicit `apply install-commit-msg` action's two files in the
  operator's own `.git/hooks/`, behind its preflight.
- Touch `core.hooksPath`, a hook manager's config, or any tracked file — the team
  enforcement lane is a human decision in a PR.
- Weaken a guard: it reports and routes; disabling is always the user's explicit act
  through the native configuration surface.
