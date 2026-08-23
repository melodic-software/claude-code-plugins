---
description: "Verify the go-format hook's runtime prerequisites and configuration for this repository. Use when: 'set up go-format', 'configure go-format', 'is go-format working', Go import/formatting fixes silently aren't happening, or the hook reported a missing prerequisite. Actions: check (read-only verification, default) | apply (resolve what check found). Re-runnable and safe."
argument-hint: "check | apply"
user-invocable: true
disable-model-invocation: true
---

## Purpose

Thin check-centric setup per the uniform setup contract (`docs/PLUGIN-PHILOSOPHY.md`
"Setup is explicit and repeatable" in the marketplace repository): `check` inspects and
reports, `apply` resolves. This plugin owns no consumer-project configuration — it runs
unconditionally (no consumer-config opt-in gate, unlike sibling formatter plugins Ruff/typos),
so the only tunable is the native `userConfig` toggle. Like `typos-format`, `goimports` has no
per-repo dependency-manager install path in the way Ruff's `.venv` does — it is conventionally
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
  time). Headless: rerun the install with the new value —
  `claude plugin install go-format@<marketplace> -s <scope> --config go_format_enabled=true`
  (repeatable per key). Against an already-installed plugin it prints `already installed` **and
  still writes the value** — verified on Claude Code 2.1.240 (a non-sensitive option at `user`
  scope: a non-default value written to an installed plugin, then restored). The short-circuit is
  about the install, not the config write. Re-verify before relying on it outside those
  conditions — a `sensitive` option, or `project`/`local` scope, were not covered. Do **not**
  uninstall to reconfigure: uninstalling drops this plugin's entire stored `pluginConfigs` entry,
  resetting every option in the README's Options reference table to its manifest default. `-s`
  defaults to `user`, so pass the scope `claude plugin list` reports for this plugin, and run from
  that project's directory for a `project`/`local` scope, or the write lands at a scope that does
  not load. This skill never writes user settings or `pluginConfigs`.
  Afterwards, keep the two claims apart. The write is issued and the stored value is what you
  passed; the RUNNING session's behavior is not. The rendered `${user_config.*}` is injected at
  skill load and each hook receives its `CLAUDE_PLUGIN_OPTION_*` from an environment fixed at
  session start, so a same-session `check` still reports the OLD value — reporting that as a
  failed write would be wrong. Verify the effective value by rerunning `check` in a **fresh
  session**, and never claim an unobserved change.

Re-running `apply` after everything passes changes nothing and reports "already configured".

## What this skill does NOT do

- Run the formatter — editing any `.go` file exercises the hook end-to-end.
- Write the plugin cache, Claude Code user settings, or `pluginConfigs`.
- Install `goimports` — installation is always the consumer's own choice and command, at the
  machine level, never a project dependency this skill records.
- Download or execute tools during `check` or `apply`.
