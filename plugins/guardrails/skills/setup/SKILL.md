---
description: "Verify the guardrails hooks' runtime prerequisites and per-guard toggle state for this machine. Use when: 'set up guardrails', 'configure guardrails', 'is guardrails working', 'which guards are on', a guard failed open with a jq notice, after tuning guard toggles, or 'install the commit-msg hook' / 'enforce the commit convention for every committer', or 'install the pre-commit content hook' / 'enforce secrets and hardcoded-path checks on every commit'. Actions: check (read-only verification, default) | apply (resolve what check found) | apply install-commit-msg (opt-in: install the tool-agnostic commit-msg convention hook into this repo's personal .git/hooks) | apply install-pre-commit-content (opt-in: install the write-path-independent secret/hardcoded-path pre-commit hook into this repo's personal .git/hooks). Re-runnable and safe."
argument-hint: "check | apply | apply install-commit-msg | apply install-pre-commit-content"
user-invocable: true
disable-model-invocation: true
---

## Purpose

Thin check-centric setup per the uniform setup contract (`docs/PLUGIN-PHILOSOPHY.md`
"Setup is explicit and repeatable" in the marketplace repository): `check` inspects and
reports, `apply` resolves. This plugin owns no consumer-project configuration — every
tunable is a native `userConfig` option (fourteen per-guard toggles plus the
`cli_flag_verify_bins`, `cli_flag_verify_skip_bins`, and `block_dangerous_git_allow`
scalars) — so `apply` is pure guidance and writes nothing.

Action routing: no argument or `check` runs the check; `apply` runs the check first, then
points at each remediation. Both are non-interactive — never prompt when the action is given.

## `check` (read-only)

The guard scripts (`${CLAUDE_PLUGIN_ROOT}/hooks/*.sh`) and `hooks.json` are the single
source of truth for the guard inventory and each guard's runtime needs.

**Read it first** — probe what it actually does, don't recite this file. Then run each probe via
Bash and report a PASS/FAIL/INFO table with one remediation line per FAIL. Do not modify anything.

When every guard's toggle is disabled, every prerequisite absence downgrades from FAIL to
INFO — each guard exits through its enabled-gate before probing anything, so a deliberately
disabled plugin is not broken. Report the probes informationally and note that re-enabling
restores the FAIL semantics.

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
  time). Headless: rerun the install with the new value —
  `claude plugin install guardrails@<marketplace> -s <scope> --config KEY=VALUE …` (repeatable per
  key). Against an already-installed plugin it prints `already installed` **and still writes the
  value** — verified on Claude Code 2.1.240 (a non-sensitive option at `user` scope: a non-default
  value written to an installed plugin, then restored). The short-circuit is about the install, not
  the config write. Re-verify before relying on it outside those conditions — a `sensitive` option,
  or `project`/`local` scope, were not covered. Do **not** uninstall to reconfigure: uninstalling
  drops this plugin's entire stored `pluginConfigs` entry, resetting every option in the README's
  Options reference table to its manifest default — every guard the operator had turned off comes
  back on, and every `*_allow`, `*_bins`, and `*_prefixes` list is discarded. `-s` defaults to
  `user`, so pass the scope `claude plugin list` reports for this plugin, and run from that
  project's directory for a `project`/`local` scope, or the write lands at a scope that does not
  load. This skill never writes user settings or `pluginConfigs`.
  Afterwards, keep the two claims apart. The write is issued and the stored value is what you
  passed; the RUNNING session's behavior is not. The rendered `${user_config.*}` is injected at
  skill load and each hook receives its `CLAUDE_PLUGIN_OPTION_*` from an environment fixed at
  session start, so a same-session `check` still reports the OLD value — reporting that as a
  failed write would be wrong. Verify the effective value by rerunning `check` in a **fresh
  session**, and never claim an unobserved change.

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

## `apply install-pre-commit-content` (opt-in, explicit argument only)

The DEPTH layer for content invariants that Write|Edit-matched guards alone cannot
close: a git `pre-commit` hook scanning every staged blob for the same high-confidence
secret patterns and hardcoded machine-path patterns the CC-layer
`secret-pattern-detection` / `hardcoded-path-check` guards use — via copies of the same
libs (`lib/secret-detection/`, `lib/path-detection/`). Catches the damage class a Bash
staged write (`jq … > /tmp/x && mv /tmp/x dest`) can introduce while skipping those
tool-matched gates. Never runs from bare `apply`; only the explicit
`install-pre-commit-content` argument installs anything.

**Lane: personal `.git/hooks/` only.** Same personal-lane contract as
`install-commit-msg` — invisible to teammates, uncommitted, removable by deleting the
hook and its `guardrails-content-lib/` directory. A committed team lane is deliberately
NOT scaffolded; when the team wants shared enforcement, add the same checks to the
repo's hook manager or CI instead.

**Preflight — refuse rather than surprise (run all, report, stop on any REFUSE):**

1. **Managed-repo detection.** `git config --get core.hooksPath` non-empty, or
   `lefthook.yml`/`.lefthook.yml`, `.husky/`, or a `pre-commit` config managing hooks →
   REFUSE: the repo's hook manager owns this surface. Remediation: add the content scan
   to the manager's own `pre-commit` entry (point it at the shipped template + libs, or
   an equivalent CI job).
2. **Existing `pre-commit` hook.** Present and NOT sentinel-marked → offer exactly two
   paths and default to refusing: **chain** (rename the existing hook to
   `pre-commit.pre-guardrails`; the installed hook runs it first and its rejection is
   final) or **refuse** (leave everything untouched). Never overwrite.
3. **Sentinel-marked hook already installed** → idempotent re-install: overwrite the
   guardrails-owned hook and refresh `guardrails-content-lib/` in place, report
   "refreshed".

**Install (on a clean preflight):** copy
`${CLAUDE_PLUGIN_ROOT}/lib/git-hooks/pre-commit-content-invariants.sh` to
`<git-dir>/hooks/pre-commit`, and copy `${CLAUDE_PLUGIN_ROOT}/lib/secret-detection/` plus
`${CLAUDE_PLUGIN_ROOT}/lib/path-detection/` to
`<git-dir>/hooks/guardrails-content-lib/{secret,path}-detection/` (resolve `<git-dir>` via
`git rev-parse --absolute-git-dir`), `chmod +x` the hook.

**Verify + report:** stage a throwaway clean file and a throwaway file containing a
synthetic high-confidence secret pattern (e.g. a `ghp_` + 36-char fixture — never a live
token); show both hook outcomes; state the removal path (delete `pre-commit` and
`guardrails-content-lib/`; restore `pre-commit.pre-guardrails` if chaining renamed one).

**Known interactions (state them in the report):**

- `--no-verify` skips pre-commit hooks; `block-no-verify` refuses that flag in Claude
  sessions — the designed exit is fixing the staged content.
- The CC-layer Write|Edit guards usually block first in a Claude session; this hook is
  the backstop for write paths those guards never see (Bash staged moves, editor
  saves, IDE commits, humans outside Claude).
- `block-hook-bypass`'s same-command staged-move detector narrows one spelling; this
  hook closes the damage class regardless of write path.

## What this skill does NOT do

- Exercise a guard — any matching tool call does that end-to-end.
- Write the plugin cache, Claude Code user settings, or `pluginConfigs`.
- Install any tool, during either `check` or `apply` — guidance only. The ONLY writes
  this skill ever performs are the explicit `apply install-commit-msg` /
  `apply install-pre-commit-content` actions' files in the operator's own `.git/hooks/`,
  behind their preflight.
- Touch `core.hooksPath`, a hook manager's config, or any tracked file — the team
  enforcement lane is a human decision in a PR.
- Weaken a guard: it reports and routes; disabling is always the user's explicit act
  through the native configuration surface.
