---
name: setup
description: "Verify the go-format hook's runtime prerequisites and configuration for this repository. Use when: 'set up go-format', 'configure go-format', 'is go-format working', Go formatting silently isn't happening, or the hook reported a missing prerequisite. Actions: check (read-only verification, default) | apply (resolve what check found). Re-runnable and safe."
argument-hint: "check | apply"
user-invocable: true
disable-model-invocation: true
---

## Purpose

Thin check-centric setup per the uniform contract: `check` inspects and reports, `apply`
resolves. This plugin owns no consumer-project configuration — gofmt has no configuration
surface at all, and the only tunable is the native `userConfig` toggle. Like `typos-format`,
gofmt has no per-repo dependency-manager install path — it ships inside the Go toolchain
itself (alongside the `go` binary), never as a project dependency. `apply` is therefore
guidance-only: it never installs anything, matching the hook's own PATH-only resolution and
the plugin philosophy's never-download-silently rule.

Action routing: no argument or `check` runs the check; `apply` runs the check first, then
prints remediation guidance for each FAIL. Both are non-interactive — never prompt when the
action is given.

## `check` (read-only)

The hook script (`${CLAUDE_PLUGIN_ROOT}/hooks/go-format.sh`) is the single source of truth for
what it requires and how it resolves things. **Read it first** — probe what it actually does,
don't recite this file. Then run each probe via Bash and report a PASS/FAIL/INFO table with one
remediation line per FAIL. Do not modify anything.

When the plugin's toggle is disabled, every prerequisite absence downgrades from FAIL to INFO
— the hook exits through its enabled-gate before probing anything, so a deliberately disabled
plugin is not broken. Report the probes informationally and note that re-enabling restores the
FAIL semantics.

1. **Bash version** — check against the hook's documented floor (README Requirements), noting
   any features the hook degrades without (telemetry's `EPOCHREALTIME`, Bash 5.0+).
2. **`jq`** — `command -v jq`. FAIL if absent: the hook then skips with a visible
   once-per-session notice instead of formatting.
3. **gofmt binary** — `command -v gofmt` (the hook resolves PATH only — gofmt ships alongside
   `go` in the Go toolchain's own bin directory, so `go version` and `gofmt -h` should resolve
   from the same location). Report the resolved path and Go's toolchain version when found.
   FAIL when absent; the hook then emits a visible once-per-session skip notice instead of
   running.
4. **Consumer configuration (informational only)** — gofmt has no configuration surface, so
   there is nothing to discover here. Report INFO: "gofmt has no configuration — the hook
   always runs the same canonical Go style." A repo that wants import-organizing (goimports)
   or stricter formatting (gofumpt) on top of gofmt does so through the toolchain plugin's
   batch `go` ecosystem entry, not this hook — report that as INFO pointing at
   `.claude/ecosystems/go.yaml`'s `opt-in` field when the toolchain plugin is also installed.
5. **Hook toggle** — report the effective `go_format_enabled` value:
   `${user_config.go_format_enabled}` (unexpanded or empty means default `true`).
6. **Hook registration** — INFO: confirm the plugin is enabled for this project
   (`/plugin` → Installed) rather than parsing settings files.

## `apply` (idempotent)

Run `check`, then for each FAIL print remediation guidance — never install anything. There is
no `apply install-gofmt`-style write path (unlike `ruff-format`/`markdown-format`): gofmt is
never installed on its own, only as part of the Go toolchain, so the only responsible action is
pointing at the official install method (`https://go.dev/dl/`) and letting the consumer choose
how to install Go at the machine level.

After the consumer installs Go themselves, re-run `check` and report its actual result — never
claim resolved without re-verifying. For everything else `apply` only points:

- missing `jq` / Bash: platform install instructions from the README Requirements section;
  this skill never installs system packages.
- toggle off: direct to `/plugin configure go-format` (interactive, any
  time). Headless: `--config` only applies on a fresh install (ignored once installed), so
  reconfigure via `claude plugin uninstall go-format` then
  `claude plugin install go-format@<marketplace> --config go_format_enabled=true`;
  this skill never writes user settings or `pluginConfigs`.
- wants stricter/import-organizing formatting: point at the toolchain plugin's
  `.claude/ecosystems/go.yaml` `opt-in` field (golangci-lint v2 `formatters.enable`) — this
  plugin imposes no rules of its own and never suggests editing a repo's golangci-lint config
  itself.

Re-running `apply` after everything passes changes nothing and reports "already configured".

## What this skill does NOT do

- Run the formatter — editing any `.go` file exercises the hook end-to-end.
- Write the plugin cache, Claude Code user settings, or `pluginConfigs`.
- Install Go or gofmt — installation is always the consumer's own choice and command, at the
  machine level, never a project dependency this skill records.
- Download or execute tools during `check` or `apply`.
