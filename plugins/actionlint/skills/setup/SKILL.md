---
description: "Verify the actionlint-check hook's runtime prerequisites and configuration for this repository. Use when: 'set up actionlint', 'configure actionlint', 'is actionlint working', workflow lint silently isn't happening, or the hook reported a missing prerequisite. Actions: check (read-only verification, default) | apply (resolve what check found). Re-runnable and safe."
argument-hint: "[check|apply]"
user-invocable: true
disable-model-invocation: true
shell: bash
---

## Pre-computed context

`check`'s tool probes ran at load time. Read these rows instead of re-issuing them; each shows the
tool's path when present, or `absent` when missing:

- `node`: !`{ command -v node 2>/dev/null || echo "absent"; }`
- `jq`: !`{ command -v jq 2>/dev/null || echo "absent"; }`
- `actionlint`: !`{ command -v actionlint 2>/dev/null || echo "absent"; }`

A row reading `[shell command execution disabled by policy]` carries no result: run that tool's
`command -v` probe via Bash instead.

## Purpose

Thin check-centric setup per the uniform setup contract (`docs/plugin-philosophy.md`
"Setup is explicit and repeatable" in the marketplace repository): `check` inspects and
reports, `apply` resolves. This plugin owns no consumer-project configuration. actionlint
auto-discovers its own optional config from the repository, and the tunables are the native
`userConfig` options (`actionlint_enabled`, `actionlint_lint_gitignored` and
`stdin_read_timeout`). Every
prerequisite is a `PATH` binary the plugin never bundles, and the plugin never installs
system packages, so `apply` is guidance-only with **no write path**. It never modifies the
repository, user settings, or the plugin cache.

Action routing: no argument or `check` runs the check; `apply` runs the check first, then
offers remediation guidance. Both are non-interactive. Never prompt when the action is given.

## `check` (read-only)

The hook script (`${CLAUDE_PLUGIN_ROOT}/hooks/actionlint-check.sh`) is the single source of
truth for what it requires and how it resolves things.

**Read it first.** Probe what it actually does, don't recite this file. Then read the
pre-computed tool rows, run the remaining probes via Bash, and report a PASS/FAIL/INFO
table with one remediation line per FAIL. Do not modify anything.

When the plugin's toggle is disabled, every prerequisite absence except `node` downgrades from
FAIL to INFO. The hook exits through its enabled-gate before probing anything, so a deliberately
disabled plugin is not broken. Report those probes informationally and note that re-enabling
restores the FAIL semantics. A missing `node` stays FAIL: the launcher runs before the enabled-gate.

1. **Bash version.** Check against the hook's documented floor (README Requirements),
   noting any features the hook degrades without (for example telemetry's `EPOCHREALTIME`,
   a Bash 5.0+ builtin).
1a. **`node`.** The pre-computed `node` row. FAIL if absent, even when the toggle is off: every hook row launches through
   `node hooks/exec-bash.mjs`, so the hook does not launch and lint does not run. The hook cannot
   report this itself; the transcript shows a hook error notice. Probed here through Bash, which
   works without the launcher.
2. **`jq`.** The pre-computed `jq` row. FAIL if absent: the hook then skips with a visible
   notice, once per session (it does not repeat this session), instead of linting.
3. **`actionlint`.** The pre-computed `actionlint` row. FAIL if absent: the hook skips workflow lint
   with a visible notice, once per session (it does not repeat this session)
   (it ships no binary of its own).
4. **actionlint config.** INFO: actionlint auto-discovers an optional
   `.github/actionlint.yaml` from the repository when present. It is not required. actionlint
   runs with its built-in defaults without one. Report whether one exists for the reader's
   awareness; its absence is not a FAIL.
5. **Hook toggle.** Report the effective `actionlint_enabled` value:
   `${user_config.actionlint_enabled}` (unexpanded or empty means default `true`; any value
   other than `true` disables the hook).
5a. **Path scope, gitignored workflow files.** INFO: report the effective
   `${user_config.actionlint_lint_gitignored}` value (unexpanded or empty means default
   `false`; only `true` lints gitignored workflow files). A tracked file that matches an
   ignore pattern is always in scope. Consult it when a workflow edit produced no lint.
5b. **Stdin read timeout.** INFO: report the effective `stdin_read_timeout` value:
   `${user_config.stdin_read_timeout}` (unexpanded or empty means default `2` seconds,
   minimum `1`). It is an IDLE bound. Any byte arriving resets it, so it fires only once
   the pipe has gone silent for that long, at which point this hook fails open. A value
   `read -t` will not accept, or `0`, falls back to the default.
6. **Hook registration.** INFO: confirm the plugin is enabled for this project
   (`/plugin` → Installed) rather than parsing settings files.

## `apply` (idempotent)

Run `check`, then for each FAIL point at the resolution. This skill installs nothing:

- missing `actionlint`: platform install guidance from the README Requirements section
  (the [actionlint install guide](https://github.com/rhysd/actionlint/blob/main/docs/install.md)).
- missing `node` / `jq` / Bash: platform install instructions from the README Requirements section.
- toggle off: reconfigure through Claude Code's native flow, per the marketplace's
  plugin-reconfiguration convention
  (<https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/plugin-reconfiguration/README.md>,
  which owns the verified-version record): interactive
  `/plugin configure actionlint@<marketplace>` any time, or headless
  `claude plugin install actionlint@<marketplace> -s <scope> --config actionlint_enabled=true`
  (repeatable per key). Against an already-installed plugin it prints `already installed`
  **and still writes the value**. Do **not** uninstall to reconfigure: that drops this plugin's
  entire stored `pluginConfigs` entry, resetting every option in the README's Options reference
  to its manifest default. Pass the scope `claude plugin list` reports for this plugin, and for a
  `project` or `local` scope run from that project's directory, so the rerun matches the existing
  install record; from the home directory pass `user`. A rejected value prints a warning yet
  exits 0, so read the output. This skill never writes user settings or `pluginConfigs`.
  Afterwards rerun `check` in a **fresh session**. The rendered
  `${user_config.*}` is injected at skill load and each hook receives its
  `CLAUDE_PLUGIN_OPTION_*` from an environment fixed at session start, so a same-session
  `check` still reports the OLD value; report the observed effective value, never an
  unobserved change.

After pointing at a remediation, re-run the relevant `check` probe live via Bash (a pre-computed row
predates the remediation, so never re-read it) and report its actual result. Never claim resolved on
the reader's report that they installed something.

Re-running `apply` after everything passes changes nothing and reports "already configured".

## Gotchas

- **A userConfig knob is reachable natively only if the manifest declares it.** Per current
  docs, `claude plugin install --config <key=value>` sets options "declared in the plugin's
  manifest". An undeclared key silently cannot be set through native config surfaces (a raw
  settings `env` block still works). That is why `stdin_read_timeout` is declared in this
  plugin's manifest even though the shared hook lib supplies its default; hook plugins reusing
  the shared lib should declare it too.
- **`--config`'s post-install behavior is undocumented, so the guidance above rests on
  observation.** The official docs describe `--config` only as a `claude plugin install` flag
  and say nothing about an already-installed plugin. The verified-version record lives only in
  the plugin-reconfiguration convention cited in `apply` above. It names which CLI release the
  still-writes claim was observed on, and which conditions it covered.
- **`-shellcheck=` / `-pyflakes=` are deliberate, and the deadlock claim is a local
  observation.** The hook disables actionlint's external run-block linters primarily for
  edit-time latency; the additional "ShellCheck deadlocks on large blocks under the Windows
  subprocess IPC path in actionlint 1.7.x" rationale is the hook author's own reproduction.
  No matching upstream rhysd/actionlint issue as of 2026-07-23; recheck when a rhysd/actionlint
  issue or release note reports ShellCheck hanging or deadlocking under the Windows subprocess
  path, which would replace the local reproduction with an upstream-confirmed cause and a fixed
  version to pin against. The latency rationale alone justifies the flags for an advisory
  edit-time hook; deep run-block linting belongs in a commit hook or CI.

## What this skill does NOT do

- Run the linter. Editing any `.github/workflows/*.yml` or `*.yaml` file exercises the hook
  end-to-end.
- Write the plugin cache, Claude Code user settings, or `pluginConfigs`. Nor the repository.
  Every prerequisite is a `PATH` binary or the native toggle, so remediation is guidance only.
- Download or execute tools during `check` beyond the read-only `command -v` presence probes.
