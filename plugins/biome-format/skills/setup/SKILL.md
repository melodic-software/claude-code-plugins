---
name: setup
description: "Verify the biome-format hook's runtime prerequisites and configuration for this repository. Use when: 'set up biome-format', 'configure biome-format', 'is biome-format working', formatting silently isn't happening, or the hook reported a missing prerequisite. Actions: check (read-only verification, default) | apply (resolve what check found). Re-runnable and safe."
argument-hint: "check | apply [install-biome]"
user-invocable: true
disable-model-invocation: true
---

## Purpose

Thin check-centric setup per the uniform contract: `check` inspects and reports, `apply`
resolves. This plugin owns no consumer-project configuration — rules come from the
repository's own Biome config, and the only tunable is the native `userConfig` toggle — so
`apply` is guidance-and-verify, with exactly one write path: the explicitly invoked
`apply install-biome` dependency install described below.

Action routing: no argument or `check` runs the check; `apply` runs the check first, then
remediation; `apply install-biome` additionally authorizes the consumer-repo dependency
install described below. All are non-interactive — never prompt when the action is given.

## `check` (read-only)

The hook script (`${CLAUDE_PLUGIN_ROOT}/hooks/biome-format.sh`) is the single source of
truth for what it requires and how it resolves things. **Read it first** — probe what it
actually does, don't recite this file. Then run each probe via Bash and report a
PASS/FAIL/INFO table with one remediation line per FAIL. Do not modify anything.

When the plugin's toggle is disabled, every prerequisite absence downgrades from FAIL to
INFO — the hook exits through its enabled-gate before probing anything, so a deliberately
disabled plugin is not broken. Report the probes informationally and note that re-enabling
restores the FAIL semantics.

1. **Bash version** — check against the hook's documented floor (README Requirements),
   noting any features the hook degrades without (for example telemetry's `EPOCHREALTIME`,
   Bash 5.0+).
2. **`jq`** — `command -v jq`. FAIL if absent: the hook then skips with a visible
   once-per-session notice instead of formatting.
3. **Biome binary** — resolve it exactly the way the hook's resolution code does: its
   repo-local install walk (the `node_modules/.bin` path it tests, walking up from the
   edited file toward the repo root) and then `PATH`. Test only what the hook tests — a
   binary the hook would not accept must not PASS here. FAIL when nothing the hook would
   resolve is present while a Biome config governs the repo; the hook then emits a visible
   once-per-session skip notice instead of formatting.
4. **Consumer Biome config** — mirror the hook's opt-in walk: it records the topmost
   governing config found walking from the edited file's directory up to the repo root, and
   deliberately accepts only the config names the hook treats as the opt-in (read the hook —
   the hidden dotted variants are intentionally excluded). Report the governing config the
   walk discovers, or INFO that none exists — absence is the opt-out by design, so the
   plugin is inert (INFO, not FAIL), matching the README's "ships no rules of its own"
   stance.
5. **Hook toggle** — report the effective `biome_format_enabled` value:
   `${user_config.biome_format_enabled}` (unexpanded or empty means default `true`).
6. **Hook registration** — INFO: confirm the plugin is enabled for this project
   (`/plugin` → Installed) rather than parsing settings files.

## `apply` (idempotent)

Run `check`, then for each FAIL offer the resolution — never install anything without the
consumer's explicit go-ahead in the invocation. `apply install-biome` adds
`@biomejs/biome` as a dev dependency in the consumer repository **using the repository's
own package manager**, resolved in order: lockfile (`pnpm-lock.yaml` → `pnpm add -D`,
`yarn.lock` → `yarn add -D`, `bun.lock`/`bun.lockb` → `bun add -d`, `package-lock.json` →
`npm install --save-dev`), then the `package.json` `"packageManager"` field when no
lockfile exists, then npm only when neither signal is present. With no `package.json`, an
ambiguous multi-lockfile state, or a lockfile that contradicts `packageManager`, stop with
manager-specific guidance instead of guessing — never introduce a competing lockfile. The
change is stated before running. For a Yarn repository, don't infer the linker — ask the
repo's own Yarn: run `yarn config get nodeLinker` in the repo. `pnp` (Berry's default when
unset) → skip the install and give guidance, because Plug'n'Play generates a loader file,
not the `node_modules/.bin` shim the hook resolves; install `@biomejs/biome` on `PATH` or
switch the linker. `node-modules`/`pnpm`, or Yarn Classic (which has no such setting and
always materializes `node_modules`) → install. The verify-after-remediation rule below is
the backstop when an install still yields no usable shim. After ANY remediation, re-run the
relevant `check` probe and report its actual result — never claim resolved on the install
command's exit code alone. For everything else `apply` only points:

- missing `jq` / Bash: platform install instructions from the README Requirements section;
  this skill never installs system packages.
- toggle off: direct to `/plugin configure biome-format` (interactive, any
  time). Headless: `--config` only applies on a fresh install (ignored once installed), so
  reconfigure via `claude plugin uninstall biome-format -s <scope>` then
  `claude plugin install biome-format@<marketplace> -s <scope> --config biome_format_enabled=true`;
  this skill never writes user settings or `pluginConfigs`. Both commands default to `-s user` —
  pass the scope `claude plugin list` reports for this plugin, and run from that project's
  directory for a `project`/`local` scope. Defaulting instead uninstalls a separate user-scope
  record while the effective install stays in place, so the reinstall lands at a scope that
  does not load.
- no Biome config: offer to create a minimal `biome.json` in the repository root only when
  explicitly asked — the plugin imposes no rules of its own.

Re-running `apply` after everything passes changes nothing and reports "already configured".

## What this skill does NOT do

- Run the formatter — editing any supported file exercises the hook end-to-end.
- Write the plugin cache, Claude Code user settings, or `pluginConfigs`.
- Download or execute tools during `check`; network use happens only in an explicitly
  requested `apply install-biome` inside the consumer repository.
