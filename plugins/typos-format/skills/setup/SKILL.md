---
description: "Verify the typos-format hook's runtime prerequisites and configuration for this repository. Use when: 'set up typos-format', 'configure typos-format', 'is typos-format working', spell-fixing silently isn't happening, or the hook reported a missing prerequisite. Actions: check (read-only verification, default) | apply (resolve what check found). Re-runnable and safe."
argument-hint: "check | apply"
user-invocable: true
disable-model-invocation: true
---

## Purpose

Thin check-centric setup per the uniform setup contract (`docs/PLUGIN-PHILOSOPHY.md`
"Setup is explicit and repeatable" in the marketplace repository): `check` inspects and
reports, `apply` resolves. This plugin owns no consumer-project configuration — rules come from
the repository's own typos config, and the only tunables are the native `userConfig` options
(the on/off toggle and the write-mode switch). Unlike sibling formatter plugins (Ruff,
markdownlint-cli2), typos has no per-repo dependency-manager install path — it is a standalone
Rust binary installed at the machine level (cargo, Homebrew, Conda, pacman, or a pre-built
binary), never as a project dependency. `apply` is therefore guidance-only: it never installs
anything, matching the hook's own PATH-only resolution and the plugin philosophy's
never-download-silently rule.

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
   once-per-session notice instead of running.
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
   `${user_config.typos_format_write_changes}` (unexpanded or empty means the shipped default
   `false`, and only the literal `true` enables writes — any other value stays report-only).
   Report-only is therefore what a default installation does: the hook still runs, still
   reports findings, and never modifies a file. Report that as **INFO, not PASS** — every
   prerequisite can pass while the one behavior the consumer came here for was never turned
   on, and the commonest reason to invoke this skill is that spell-fixing is not happening.
   Name the remediation in the same line rather than leaving the reader to infer it.
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
  time). Headless: rerun the install with the new value —
  `claude plugin install typos-format@<marketplace> -s <scope> --config typos_format_enabled=true`
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
- report-only mode (`typos_format_write_changes` unset, or set to anything but `true`): the
  hook is working as shipped — writes were never turned on — so this is a configuration
  answer, not a repair. Say so, then offer the same `/plugin configure typos-format` route
  (or the headless install rerun above, with `--config typos_format_write_changes=true`),
  and state what turning it on accepts: last-writer-wins ordering against any
  sibling hook that rewrites the same file. For the opposite case — writes already on and a
  few corrections unwanted — the fit is allow-listing those words in the repository's typos
  config, not switching the whole hook back to report-only.
- no typos config: offer to create a minimal `_typos.toml` in the repository root only when
  explicitly asked — the plugin imposes no rules of its own.

Re-running `apply` after everything passes changes nothing and reports "already configured".

## What this skill does NOT do

- Run the spell-checker — editing any file exercises the hook end-to-end.
- Write the plugin cache, Claude Code user settings, or `pluginConfigs`.
- Install `typos` — installation is always the consumer's own choice and command, at the
  machine level, never a project dependency this skill records.
- Download or execute tools during `check` or `apply`.
