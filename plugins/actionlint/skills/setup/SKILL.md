---
name: setup
description: "Verify the actionlint-check hook's runtime prerequisites and configuration for this repository. Use when: 'set up actionlint', 'configure actionlint', 'is actionlint working', workflow lint silently isn't happening, or the hook reported a missing prerequisite. Actions: check (read-only verification, default) | apply (resolve what check found). Re-runnable and safe."
argument-hint: "check | apply"
user-invocable: true
disable-model-invocation: true
---

## Purpose

Thin check-centric setup per the uniform contract: `check` inspects and reports, `apply`
resolves. This plugin owns no consumer-project configuration — actionlint auto-discovers its
own optional config from the repository, and the only tunable is the native `userConfig`
toggle. Every prerequisite is a `PATH` binary the plugin never bundles, and the plugin never
installs system packages, so `apply` is guidance-only with **no write path** — it never
modifies the repository, user settings, or the plugin cache.

Action routing: no argument or `check` runs the check; `apply` runs the check first, then
offers remediation guidance. Both are non-interactive — never prompt when the action is given.

## `check` (read-only)

The hook script (`${CLAUDE_PLUGIN_ROOT}/hooks/actionlint-check.sh`) is the single source of
truth for what it requires and how it resolves things. **Read it first** — probe what it
actually does, don't recite this file. Then run each probe via Bash and report a
PASS/FAIL/INFO table with one remediation line per FAIL. Do not modify anything.

When the plugin's toggle is disabled, every prerequisite absence downgrades from FAIL to
INFO — the hook exits through its enabled-gate before probing anything, so a deliberately
disabled plugin is not broken. Report the probes informationally and note that re-enabling
restores the FAIL semantics.

1. **Bash version** — check against the hook's documented floor (README Requirements),
   noting any features the hook degrades without (for example telemetry's `EPOCHREALTIME`,
   a Bash 5.0+ builtin).
2. **`jq`** — `command -v jq`. FAIL if absent: the hook then skips with a visible
   once-per-session notice instead of linting.
3. **`actionlint`** — `command -v actionlint`. FAIL if absent: the hook skips workflow lint
   with a visible once-per-session notice (it ships no binary of its own).
4. **actionlint config** — INFO: actionlint auto-discovers an optional
   `.github/actionlint.yaml` from the repository when present. It is not required — actionlint
   runs with its built-in defaults without one. Report whether one exists for the reader's
   awareness; its absence is not a FAIL.
5. **Hook toggle** — report the effective `actionlint_enabled` value:
   `${user_config.actionlint_enabled}` (unexpanded or empty means default `true`; any value
   other than `true` disables the hook).
6. **Hook registration** — INFO: confirm the plugin is enabled for this project
   (`/plugin` → Installed) rather than parsing settings files.

## `apply` (idempotent)

Run `check`, then for each FAIL point at the resolution — this skill installs nothing:

- missing `actionlint`: platform install guidance from the README Requirements section
  (the [actionlint install guide](https://github.com/rhysd/actionlint/blob/main/docs/install.md)).
- missing `jq` / Bash: platform install instructions from the README Requirements section.
- toggle off: direct to `/plugin configure actionlint` or
  `claude plugin install actionlint@<marketplace> --config actionlint_enabled=true`;
  this skill never writes user settings or `pluginConfigs`.

After pointing at a remediation, re-run the relevant `check` probe and report its actual
result — never claim resolved on the reader's report that they installed something.

Re-running `apply` after everything passes changes nothing and reports "already configured".

## What this skill does NOT do

- Run the linter — editing any `.github/workflows/*.yml` or `*.yaml` file exercises the hook
  end-to-end.
- Write anything: not the repository, not Claude Code user settings, not `pluginConfigs`, not
  the plugin cache. Every prerequisite is a `PATH` binary or the native toggle, so remediation
  is guidance only.
- Download or execute tools during `check` beyond the read-only `command -v` presence probes.
