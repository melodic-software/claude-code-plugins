---
name: setup
description: "Verify the go-format hook's runtime prerequisites and configuration for this repository. Use when: 'set up go-format', 'configure go-format', 'is go-format working', Go import/formatting fixes silently aren't happening, or the hook reported a missing prerequisite. Actions: check (read-only verification, default) | apply (resolve what check found). Re-runnable and safe."
argument-hint: "check | apply"
user-invocable: true
disable-model-invocation: true
---

## Purpose

Thin check-centric setup per the uniform contract: `check` inspects and reports, `apply`
resolves. This plugin owns no consumer-project configuration — it runs unconditionally (no
consumer-config opt-in gate, unlike sibling formatter plugins Ruff/typos), so the only tunable
is the native `userConfig` toggle. Like `typos-format`, `goimports` has no per-repo
dependency-manager install path in the way Ruff's `.venv` does — it is conventionally
`go install`ed to the machine-global `$GOPATH/bin`, never as a project dependency. `apply` is
therefore guidance-only: it never installs anything, matching the hook's own PATH-only
resolution and the plugin philosophy's never-download-silently rule.

Action routing: no argument or `check` runs the check; `apply` runs the check first, then
prints remediation guidance for each FAIL. Both are non-interactive — never prompt when the
action is given.

## `check` (read-only)

The hook script (`${CLAUDE_PLUGIN_ROOT}/hooks/go-format.sh`) is the single source of truth for
what it requires and how it resolves things. **Read it first** — probe what it actually does,
don't recite this file. Then run each probe via Bash and report a PASS/FAIL/INFO table with one
remediation line per FAIL. Do not modify anything.

When the plugin's toggle is disabled, every prerequisite absence downgrades from FAIL to
INFO — the hook exits through its enabled-gate before probing anything, so a deliberately
disabled plugin is not broken. Report the probes informationally and note that re-enabling
restores the FAIL semantics.

1. **Bash version** — check against the hook's documented floor (README Requirements),
   noting any features the hook degrades without (telemetry's `EPOCHREALTIME`, Bash 5.0+).
2. **`jq`** — `command -v jq`. FAIL if absent: the hook then skips with a visible
   once-per-session notice instead of formatting.
3. **`goimports` binary** — `command -v goimports` (the hook resolves PATH only — no
   `.venv`-style per-repo convention). Report the resolved path and `goimports -h`'s first line
   when found (goimports has no `--version` flag; the help header is the closest signal). FAIL
   when absent — the hook then emits a visible once-per-session skip notice instead of running.
4. **Hook toggle** — report the effective `go_format_enabled` value:
   `${user_config.go_format_enabled}` (unexpanded or empty means default `true`).
5. **Hook registration** — INFO: confirm the plugin is enabled for this project
   (`/plugin` → Installed) rather than parsing settings files.

There is no consumer-config probe (unlike `typos-format`'s config-walk check) — this hook runs
unconditionally by design; report that plainly as INFO, not as a gap.

## `apply` (idempotent)

Run `check`, then for each FAIL print remediation guidance — never install anything. There is
no `apply install-goimports`-style write path: `go install golang.org/x/tools/cmd/goimports@latest`
writes to the machine-global `$GOPATH/bin` (not project-scoped) and `@latest` is not
idempotent-pinned, so the only responsible action is pointing at the command and letting the
consumer run it themselves.

After the consumer installs `goimports` themselves, re-run `check` and report its actual
result — never claim resolved without re-verifying. For everything else `apply` only points:

- missing `goimports`: `go install golang.org/x/tools/cmd/goimports@latest` (requires a Go
  toolchain: https://go.dev/dl/).
- missing `jq` / Bash: platform install instructions from the README Requirements section;
  this skill never installs system packages.
- toggle off: direct to `/plugin configure go-format` (interactive, any
  time). Headless: `--config` only applies on a fresh install (ignored once installed), so
  reconfigure via `claude plugin uninstall go-format` then
  `claude plugin install go-format@<marketplace> --config go_format_enabled=true`;
  this skill never writes user settings or `pluginConfigs`.

Re-running `apply` after everything passes changes nothing and reports "already configured".

## What this skill does NOT do

- Run the formatter — editing any `.go` file exercises the hook end-to-end.
- Write the plugin cache, Claude Code user settings, or `pluginConfigs`.
- Install `goimports` — installation is always the consumer's own choice and command, at the
  machine level, never a project dependency this skill records.
- Download or execute tools during `check` or `apply`.
