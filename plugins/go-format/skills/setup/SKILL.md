---
description: "Verify the go-format hook's runtime prerequisites and configuration for this repository. Use when: 'set up go-format', 'configure go-format', 'is go-format working', Go import/formatting fixes silently aren't happening, or the hook reported a missing prerequisite. Actions: check (read-only verification, default) | apply (resolve what check found). Re-runnable and safe."
argument-hint: "check | apply"
user-invocable: true
disable-model-invocation: true
shell: bash
---

## Pre-computed context

`check`'s tool probes ran at load time. Read these rows instead of re-issuing them; each shows the
tool's path when present, or `absent` when missing:

- `jq`: !`{ command -v jq 2>/dev/null || echo "absent"; }`
- `node`: !`{ command -v node 2>/dev/null || echo "absent"; }`
- `goimports`: !`{ command -v goimports 2>/dev/null || echo "absent"; }`

A row reading `[shell command execution disabled by policy]` carries no result: run that tool's
`command -v` probe via Bash instead.

## Purpose

Thin check-centric setup per the uniform setup contract (`docs/plugin-philosophy.md`
"Setup is explicit and repeatable" in the marketplace repository): `check` inspects and
reports, `apply` resolves. This plugin owns no consumer-project configuration. It has
no consumer-config opt-in gate (unlike sibling formatter plugins Ruff/typos), so the only
tunables are the two native `userConfig` options, `go_format_enabled` and
`go_format_lint_gitignored`. Like `typos-format`, `goimports` has no
per-repo dependency-manager install path in the way Ruff's `.venv` does. It is conventionally
`go install`ed to the machine-global `$GOPATH/bin`, never as a project dependency. `apply` is
therefore guidance-only: it never installs anything, matching the hook's own PATH-only
resolution and the plugin philosophy's never-download-silently rule.

Action routing: no argument or `check` runs the check; `apply` runs the check first, then
prints remediation guidance for each FAIL. Both are non-interactive. Never prompt when the
action is given.

## `check` (read-only)

The hook script (`${CLAUDE_PLUGIN_ROOT}/hooks/go-format.sh`) is the single source of truth for
what it requires and how it resolves things.

**Read it first.** Probe what it actually does, don't recite this file. Then read the
pre-computed tool rows, run the remaining probes via Bash, and report a PASS/FAIL/INFO
table with one remediation line per FAIL. Do not modify anything.

When the plugin's toggle is disabled, every prerequisite absence except `node` downgrades from
FAIL to INFO. The hook exits through its enabled-gate before probing anything, so a deliberately
disabled plugin is not broken. Report those probes informationally and note that re-enabling
restores the FAIL semantics. A missing `node` stays FAIL in either state: Claude Code launches
`node` before the launcher can read the toggle, so both hook rows fail to start.

1. **Bash version.** Check against the hook's documented floor (README Requirements),
   noting any features the hook degrades without (telemetry's `EPOCHREALTIME`, Bash 5.0+).
2. **`jq`.** The pre-computed `jq` row. FAIL if absent: the hook then skips with a visible
   once-per-session notice instead of formatting.
3. **`node`.** The pre-computed `node` row. FAIL if absent: every hook row launches through
   `node hooks/exec-bash.mjs`, so without node the hooks do not start and nothing is enforced.
   The row reflects Bash's PATH, while Claude Code resolves the hook's `node` from its own
   environment (`docs/formatter-path-probes.md`), so a PASS here does not establish that hooks
   launch. If hooks fail to start despite a PASS, report hook availability as unestablished.
4. **`goimports` binary.** The pre-computed `goimports` row (the hook resolves PATH only, no
   `.venv`-style per-repo convention). Report the resolved path and `goimports -h`'s first line
   when found (goimports has no `--version` flag; the help header is the closest signal). FAIL
   when absent. The hook then emits a visible once-per-session skip notice instead of running.
5. **Hook toggle.** Report the effective `go_format_enabled` value:
   `${user_config.go_format_enabled}` (unexpanded or empty means default `true`).
6. **Gitignored files.** Report the effective `go_format_lint_gitignored` value:
   `${user_config.go_format_lint_gitignored}` (unexpanded or empty means default `false`). At
   `false` the hook skips files the repository gitignores; a tracked file matching an ignore
   pattern stays in scope.
7. **Hook registration.** INFO: confirm the plugin is enabled for this project
   (`/plugin` → Installed) rather than parsing settings files.

There is no consumer-config probe (unlike `typos-format`'s config-walk check). This hook has
no consumer-config gate by design; report that plainly as INFO, not as a gap.

## `apply` (idempotent)

Run `check`, then for each FAIL print remediation guidance. Never install anything. There is
no `apply install-goimports`-style write path: `go install golang.org/x/tools/cmd/goimports@latest`
writes to the machine-global `$GOPATH/bin` (not project-scoped) and `@latest` is not
idempotent-pinned, so the only responsible action is pointing at the command and letting the
consumer run it themselves.

After the consumer installs `goimports` themselves, re-run `check` with live Bash probes (the
pre-computed rows predate the install) and report its actual result. Never claim resolved without
re-verifying. For everything else `apply` only points:

- missing `goimports`: `go install golang.org/x/tools/cmd/goimports@latest` (requires a Go
  toolchain: https://go.dev/dl/).
- missing `node` / `jq` / Bash: platform install instructions from the README Requirements section;
  this skill never installs system packages.
- toggle off: the marketplace's plugin-reconfiguration convention owns the routes, the caveats,
  the measured CLI behavior (including that a rerun against an already-installed plugin still
  writes the value) and its verification record
  (<https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/plugin-reconfiguration/README.md>).
  Two consumer-run routes: interactive `/plugin configure go-format@<marketplace>`, or headless
  `claude plugin install go-format@<marketplace> -s user --config go_format_enabled=false`
  (`go_format_lint_gitignored` is set the same way). Print these four caveats with it:
  - Never uninstall to reconfigure: it drops this plugin's entire stored `pluginConfigs` entry and
    resets every option to its manifest default.
  - Scope. Pass `-s user`. `-s` places the install record and `enabledPlugins`; the option value
    always lands in user settings. Do not copy a scope from `claude plugin list`: a rerun at
    another scope adds an install record at that scope and enables the plugin there. When the
    working directory is the home directory, project scope and user scope are the same settings
    file, so the list can label that one file as both `user` and `project`.
  - Observation is next-session: a same-session `check` still reports the OLD value, so rerun
    `check` in a **fresh session** and report the observed effective value, never an unobserved
    change.
  - Read the command's output, not its exit code: a rejected value prints a warning yet exits 0.

  This skill never writes user settings or `pluginConfigs`.

Re-running `apply` after everything passes changes nothing and reports "already configured".

## What this skill does NOT do

- Run the formatter. Editing any `.go` file exercises the hook end-to-end.
- Write the plugin cache, Claude Code user settings, or `pluginConfigs`.
- Install `goimports`. Installation is always the consumer's own choice and command, at the
  machine level, never a project dependency this skill records.
- Download or execute tools during `check` or `apply`.
