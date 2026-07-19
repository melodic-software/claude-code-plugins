---
name: setup
description: "Verify the guardrails hooks' runtime prerequisites and per-guard toggle state for this machine. Use when: 'set up guardrails', 'configure guardrails', 'is guardrails working', 'which guards are on', a guard failed open with a jq notice, or after tuning guard toggles. Actions: check (read-only verification, default) | apply (resolve what check found). Re-runnable and safe."
argument-hint: "check | apply"
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
  reconfigure via `claude plugin uninstall guardrails` then
  `claude plugin install guardrails@<marketplace> --config KEY=VALUE …` (repeatable);
  this skill never writes user settings or `pluginConfigs`.

Re-running `apply` after everything passes changes nothing and reports "already configured".

## What this skill does NOT do

- Exercise a guard — any matching tool call does that end-to-end.
- Write the plugin cache, Claude Code user settings, or `pluginConfigs`.
- Install any tool, during either `check` or `apply` — guidance only.
- Weaken a guard: it reports and routes; disabling is always the user's explicit act
  through the native configuration surface.
