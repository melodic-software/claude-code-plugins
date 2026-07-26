---
name: setup
description: "Verify the typos-format hook's runtime prerequisites and configuration for this repository. Use when: 'set up typos-format', 'configure typos-format', 'is typos-format working', spell-fixing silently isn't happening, or the hook reported a missing prerequisite. Actions: check (read-only verification, default) | apply (resolve what check found). Re-runnable and safe."
argument-hint: "check | apply"
user-invocable: true
disable-model-invocation: true
---

## Purpose

Thin check-centric setup per the uniform contract: `check` inspects and reports, `apply`
resolves. This plugin owns no consumer-project configuration — rules come from the
repository's own typos config, and the only tunables are the native `userConfig` options
(the on/off toggle and the write-mode switch). Unlike
sibling formatter plugins (Ruff, markdownlint-cli2), typos has no per-repo dependency-manager
install path — it is a standalone Rust binary installed at the machine level (cargo, Homebrew,
Conda, pacman, or a pre-built binary), never as a project dependency. `apply` is therefore
guidance-only: it never installs anything, matching the hook's own PATH-only resolution and the
plugin philosophy's never-download-silently rule.

Action routing: no argument or `check` runs the check; `apply` runs the check first, then
prints remediation guidance for each FAIL. Both are non-interactive — never prompt when the
action is given.

## `check` (read-only)

The hook script (`${CLAUDE_PLUGIN_ROOT}/hooks/typos-format.sh`) is the single source of truth
for what it requires and how it resolves things. **Read it first** — probe what it actually
does, don't recite this file. Then run each probe via Bash and report a PASS/FAIL/INFO table
with one remediation line per FAIL. Do not modify anything.

When the plugin's toggle is disabled, every prerequisite absence downgrades from FAIL to
INFO — the hook exits through its enabled-gate before probing anything, so a deliberately
disabled plugin is not broken. Report the probes informationally and note that re-enabling
restores the FAIL semantics.

1. **Bash version** — check against the hook's documented floor (README Requirements),
   noting any features the hook degrades without (telemetry's `EPOCHREALTIME`, Bash 5.0+).
2. **`jq`** — `command -v jq`. FAIL if absent: the hook then skips with a visible
   once-per-session notice instead of fixing typos.
3. **typos binary** — `command -v typos` (the hook resolves PATH only — no `.venv`-style
   per-repo convention). Report the resolved path and `typos --version` output when found.
   FAIL when absent; the hook then emits a visible once-per-session skip notice instead of
   running.
4. **Consumer typos config (informational only)** — the hook runs unconditionally and never
   gates on a config existing; typos resolves its own governing config (if any) directly from
   the file path it is given. Report whether a `typos.toml`, `_typos.toml`, `.typos.toml`, a
   `Cargo.toml` with `[workspace.metadata.typos]`/`[package.metadata.typos]`, or a
   `pyproject.toml` with `[tool.typos]` governs the repo, purely as INFO — its presence or
   absence never changes whether the hook runs.
5. **Hook toggle** — report the effective `typos_format_enabled` value:
   `${user_config.typos_format_enabled}` (unexpanded or empty means default `true`).
6. **Write mode** — report the effective `typos_format_write_changes` value:
   `${user_config.typos_format_write_changes}` (unexpanded or empty means default `true`).
   When it is `false` the hook is in report-only mode: it still runs, still reports findings,
   and never modifies a file. Report that as **INFO, not PASS** — every prerequisite can pass
   while the one behavior the consumer came here for is deliberately off, and the commonest
   reason to invoke this skill is that spell-fixing is not happening. Name the remediation in
   the same line rather than leaving the reader to infer it.
7. **Hook registration** — INFO: confirm the plugin is enabled for this project
   (`/plugin` → Installed) rather than parsing settings files.

## `apply` (idempotent)

Run `check`, then for each FAIL print remediation guidance — never install anything. There is
no `apply install-typos`-style write path (unlike `ruff-format`/`markdown-format`): typos has
no clean per-repo dependency-manager story, so the only responsible action is pointing at the
official install methods (`https://github.com/crate-ci/typos#install` — cargo, Homebrew,
Conda, pacman, or a pre-built binary; pick the platform-appropriate one to surface) and letting
the consumer choose how to install it at the machine level.

After the consumer installs `typos` themselves, re-run `check` and report its actual result —
never claim resolved without re-verifying. For everything else `apply` only points:

- missing `jq` / Bash: platform install instructions from the README Requirements section;
  this skill never installs system packages.
- toggle off: direct to `/plugin configure typos-format` (interactive, any
  time). Headless: `--config` only applies on a fresh install (ignored once installed), so
  reconfigure via `claude plugin uninstall typos-format -s <scope>` then
  `claude plugin install typos-format@<marketplace> -s <scope> --config typos_format_enabled=true`;
  this skill never writes user settings or `pluginConfigs`. Both commands default to `-s user` —
  pass the scope `claude plugin list` reports for this plugin, and run from that project's
  directory for a `project`/`local` scope. Defaulting instead uninstalls a separate user-scope
  record while the effective install stays in place, so the reinstall lands at a scope that
  does not load.
- report-only mode on (`typos_format_write_changes=false`): the hook is working as configured,
  so this is a configuration answer, not a repair. Say so, then offer the same
  `/plugin configure typos-format` route (or the scope-preserving uninstall/reinstall
  `--config typos_format_write_changes=true` recipe above) — and note the alternative that
  usually fits better: keeping writes on and allow-listing the specific words in the
  repository's typos config, since report-only turns off every correction to suppress a few.
- no typos config: offer to create a minimal `_typos.toml` in the repository root only when
  explicitly asked — the plugin imposes no rules of its own.

Re-running `apply` after everything passes changes nothing and reports "already configured".

## What this skill does NOT do

- Run the spell-checker — editing any file exercises the hook end-to-end.
- Write the plugin cache, Claude Code user settings, or `pluginConfigs`.
- Install `typos` — installation is always the consumer's own choice and command, at the
  machine level, never a project dependency this skill records.
- Download or execute tools during `check` or `apply`.
