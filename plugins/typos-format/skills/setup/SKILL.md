---
name: setup
description: "Verify the typos-format hook's runtime prerequisites and configuration for this repository. Use when: 'set up typos-format', 'configure typos-format', 'is typos-format working', spell-check fixes silently aren't happening, or the hook reported a missing prerequisite. Actions: check (read-only verification, default) | apply (resolve what check found). Re-runnable and safe."
argument-hint: "check | apply"
user-invocable: true
disable-model-invocation: true
---

## Purpose

Thin check-centric setup per the uniform contract: `check` inspects and reports, `apply`
resolves. This plugin owns no consumer-project configuration — the spelling dictionary and
its allowlist come from `typos`' own built-in list plus the repository's own `_typos.toml`,
and the only tunable is the native `userConfig` toggle. `typos` is a standalone system
binary the plugin never bundles or installs into a repository, so `apply` is
guidance-only with **no write path** — it never modifies the repository, user settings, or
the plugin cache.

Action routing: no argument or `check` runs the check; `apply` runs the check first, then
offers remediation guidance. Both are non-interactive — never prompt when the action is given.

## `check` (read-only)

The hook script (`${CLAUDE_PLUGIN_ROOT}/hooks/typos-format.sh`) is the single source of
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
   once-per-session notice instead of fixing anything.
3. **`typos`** — `command -v typos`. FAIL if absent: the hook skips with a visible
   once-per-session notice. Then confirm the resolved binary actually executes — run
   `typos --version` (present-but-broken is still a FAIL, with the execution error in the
   remediation line).
4. **Consumer `_typos.toml`** — mirror `typos`' own discovery: it walks up from a target
   file toward the filesystem root looking for `typos.toml`, `_typos.toml`, `.typos.toml`,
   `Cargo.toml` (`[workspace.metadata.typos]`/`[package.metadata.typos]`), or
   `pyproject.toml` (`[tool.typos]`), stopping at the first hit — run
   `typos --dump-config -` from the repository root to see the effective merged config
   typos itself resolves, and report whether any project-level config file exists (or
   INFO that none does — absence is not a defect; typos' built-in dictionary still runs).
5. **Hook toggle** — report the effective `typos_format_enabled` value:
   `${user_config.typos_format_enabled}` (unexpanded or empty means default `true`).
6. **Hook registration** — INFO: confirm the plugin is enabled for this project
   (`/plugin` → Installed) rather than parsing settings files.

## `apply` (idempotent)

Run `check`, then for each FAIL point at the resolution — this skill installs nothing:

- missing `typos`: point at the
  [install guide](https://github.com/crate-ci/typos#install) (prebuilt release binary, or
  `cargo install typos-cli --locked` / `brew install typos-cli` / `conda install typos` /
  `pacman -S typos`, whichever the repository's own toolchain already favors); this skill
  never installs system packages.
- missing `jq` / Bash: platform install instructions from the README Requirements section.
- a false positive (a name, acronym, or intentional spelling `typos` flags): point at the
  [false positives](https://github.com/crate-ci/typos#false-positives) guidance —
  `extend-words`, `extend-identifiers`, or `extend-ignore-re` in `_typos.toml` — but this
  skill does not write the file; the correction is the consumer's own call.
- toggle off: direct to `/plugin configure typos-format` (interactive, any
  time). Headless: `--config` only applies on a fresh install (ignored once installed), so
  reconfigure via `claude plugin uninstall typos-format` then
  `claude plugin install typos-format@<marketplace> --config typos_format_enabled=true`;
  this skill never writes user settings or `pluginConfigs`.

After pointing at a remediation, re-run the relevant `check` probe and report its actual
result — never claim resolved on the reader's report that they installed something.

Re-running `apply` after everything passes changes nothing and reports "already configured".

## What this skill does NOT do

- Run the spell checker — editing any file exercises the hook end-to-end. The only
  execution `check` performs is the harmless `typos --version` liveness probe and a
  read-only `typos --dump-config -`; it never fixes or touches repository content.
- Write anything: not the repository (including `_typos.toml`), not Claude Code user
  settings, not `pluginConfigs`, not the plugin cache. Every prerequisite is a `PATH`
  binary or the native toggle, so remediation is guidance only.
- Download or execute tools during `check` beyond the read-only presence and
  `--version`/`--dump-config` probes.
