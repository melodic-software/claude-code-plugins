---
description: "Verify the guardrails hooks' runtime prerequisites and per-guard toggle state for this machine. Use when: 'set up guardrails', 'configure guardrails', 'is guardrails working', 'which guards are on', a guard failed open with a jq notice, after tuning guard toggles, or 'install the commit-msg hook' / 'enforce the commit convention for every committer', or 'install the pre-commit content hook' / 'enforce secrets and hardcoded-path checks on every commit'. Actions: check (read-only verification, default) | apply (resolve what check found) | apply install-commit-msg (opt-in: install the tool-agnostic commit-msg convention hook into this repo's personal .git/hooks) | apply install-pre-commit-content (opt-in: install the write-path-independent secret/hardcoded-path pre-commit hook into this repo's personal .git/hooks). Re-runnable and safe."
argument-hint: "check | apply | apply install-commit-msg | apply install-pre-commit-content"
user-invocable: true
disable-model-invocation: true
---

## Purpose

Thin check-centric setup per the uniform setup contract (`docs/PLUGIN-PHILOSOPHY.md`
"Setup is explicit and repeatable" in the marketplace repository): `check` inspects and
reports, `apply` resolves. This plugin owns no consumer-project configuration. Every
tunable is a native `userConfig` option (one enable toggle per guard plus the
`cli_flag_verify_bins`, `cli_flag_verify_skip_bins`, and `block_dangerous_git_allow`
scalars), so `apply` is pure guidance and writes nothing.

Action routing: no argument or `check` runs the check; `apply` runs the check first, then
points at each remediation. Both are non-interactive. Never prompt when the action is given.

## `check` (read-only)

The guard scripts (`${CLAUDE_PLUGIN_ROOT}/hooks/*.sh`) and `hooks.json` are the single
source of truth for the guard inventory and each guard's runtime needs.

**Read it first.** Probe what it actually does, don't recite this file. Then run each probe via
Bash and report a PASS/FAIL/INFO table with one remediation line per FAIL. Do not modify anything.

When every guard's toggle is disabled, every prerequisite absence downgrades from FAIL to
INFO. Each guard exits through its enabled-gate before probing anything, so a deliberately
disabled plugin is not broken. Report the probes informationally and note that re-enabling
restores the FAIL semantics.

1. **Bash 5.0+.** The guards' documented runtime floor (Git Bash on native Windows).
   FAIL below the floor with the README Requirements remediation.
2. **`jq`.** `command -v jq`. FAIL if absent: per the README, every guard then fails
   OPEN (disabled) with a one-line stderr notice. The machine is unguarded, which is
   exactly what this check exists to surface.
3. **Per-guard toggles.** Report each guard's effective `<guard>_enabled` value, one row per
   guard, so the user sees the live guard surface at a glance. The effective value is the
   configured option, else that guard's `default` in `plugin.json`; the guards read it as the
   `CLAUDE_PLUGIN_OPTION_<GUARD>_ENABLED` export. Defaults differ per guard (the advisory
   opt-in guards ship `false`), so take each default from the manifest and never assume `true`.
4. **`cli-flag-verify` scan surface.** Report the effective `cli_flag_verify_bins` /
   `cli_flag_verify_skip_bins` values and INFO-note the guard's own behavior for scanned
   binaries missing from `PATH` (skipped, never flagged, per the guard source).
5. **`block-dangerous-git` allowlist.** Report the effective `block_dangerous_git_allow`
   value (patterns only, verbatim; it contains no secrets by design).
6. **Hook registration.** INFO: confirm the plugin is enabled for this project
   (`/plugin` → Installed) rather than parsing settings files.

## `apply` (idempotent)

Run `check`, then for each FAIL point at the resolution. Every prerequisite is a system
tool and every tunable is native `userConfig`, so `apply` installs nothing and writes
nothing. It only points:

- missing `jq` / old Bash: platform install instructions from the README Requirements
  section; this skill never installs system packages.
- any toggle or scalar change: reconfigure through Claude Code's native flow, per the
  marketplace's plugin-reconfiguration convention
  (<https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/plugin-reconfiguration/README.md>,
  which owns the verified-version record): interactive `/plugin configure guardrails@<marketplace>`
  any time, or headless `claude plugin install guardrails@<marketplace> -s <scope> --config KEY=VALUE`
  (repeatable per key) — against an already-installed plugin it prints `already installed` and
  still writes the value. Do **not** uninstall to reconfigure: that drops the plugin's entire
  stored `pluginConfigs` entry, resetting every option in the README's Options reference to its
  manifest default. `-s` defaults to `user`; pass the scope `claude plugin list` reports, and run
  from that project's directory for a `project`/`local` scope, or the write lands at a scope that
  does not load. This skill never writes user settings or `pluginConfigs`. Afterwards rerun
  `check` in a **fresh session** — the rendered `${user_config.*}` and each hook's
  `CLAUDE_PLUGIN_OPTION_*` are fixed at session start, so a same-session `check` still reports
  the OLD value; report the observed effective value, never an unobserved change.

Re-running `apply` after everything passes changes nothing and reports "already configured".

## `apply install-commit-msg` (opt-in, explicit argument only)

The DEPTH layer of commit-convention enforcement: a git `commit-msg` hook validating every
commit on this machine in this repo: editor commits, `git commit -F <file>`, IDE
integrations, humans outside Claude, against the same team-tracked pattern the CC-layer
`block-convention-violation` guard reads, through a copy of the same resolver. Never runs
from bare `apply`; only the explicit `install-commit-msg` argument installs anything.

Read [context/install-commit-msg.md](context/install-commit-msg.md) when invoked with
`apply install-commit-msg`: the personal-lane contract, the refuse-rather-than-surprise
preflight, the install and verify steps, and the known interactions to state in the report.

## `apply install-pre-commit-content` (opt-in, explicit argument only)

The DEPTH layer for content invariants that Write|Edit-matched guards alone cannot close: a
git `pre-commit` hook scanning every staged blob for the same secret and hardcoded-path
patterns the CC-layer `secret-pattern-detection` / `hardcoded-path-check` guards use.
Catches the damage class a Bash staged write can introduce while skipping those
tool-matched gates. Never runs from bare `apply`; only the explicit
`install-pre-commit-content` argument installs anything.

Read [context/install-pre-commit-content.md](context/install-pre-commit-content.md) when
invoked with `apply install-pre-commit-content`: the personal-lane contract, the
refuse-rather-than-surprise preflight, the install and verify steps, and the known
interactions to state in the report.

## What this skill does NOT do

- Exercise a guard. Any matching tool call does that end-to-end.
- Write the plugin cache, Claude Code user settings, or `pluginConfigs`.
- Install any tool, during either `check` or `apply`. Guidance only. The ONLY writes
  this skill ever performs are the explicit `apply install-commit-msg` /
  `apply install-pre-commit-content` actions' files in the operator's own `.git/hooks/`,
  behind their preflight.
- Touch `core.hooksPath`, a hook manager's config, or any tracked file. The team
  enforcement lane is a human decision in a PR.
- Weaken a guard: it reports and routes; disabling is always the user's explicit act
  through the native configuration surface.
