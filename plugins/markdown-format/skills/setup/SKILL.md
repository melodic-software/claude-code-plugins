---
name: setup
description: "Verify the markdown-format hook's runtime prerequisites and configuration for this repository. Use when: 'set up markdown-format', 'configure markdown-format', 'is markdown-format working', formatting silently isn't happening, or the hook reported a missing prerequisite. Actions: check (read-only verification, default) | apply (resolve what check found). Re-runnable and safe."
argument-hint: "check | apply"
user-invocable: true
disable-model-invocation: true
---

## Purpose

Thin check-centric setup per the uniform contract: `check` inspects and reports, `apply`
resolves. This plugin owns no consumer-project configuration — rules come from the
repository's own markdownlint config, and the only tunable is the native `userConfig`
toggle — so `apply` is guidance-and-verify, never a repository write.

Action routing: no argument or `check` runs the check; `apply` runs the check first, then
remediation. Both are non-interactive — never prompt when the action is given.

## `check` (read-only)

Run each probe via Bash and report a PASS/FAIL/INFO table with one remediation line per FAIL.
Do not modify anything.

1. **Bash version** — `bash --version | head -1`. Requires 3.2+; note that telemetry needs
   5.0+ (`EPOCHREALTIME`) and formatting still runs without it.
2. **`jq`** — `command -v jq`. FAIL if absent: the hook then skips with a visible
   once-per-session notice instead of formatting.
3. **`markdownlint-cli2`** — resolvable as `command -v markdownlint-cli2` OR
   `<repo-root>/node_modules/.bin/markdownlint-cli2` (the hook's two sanctioned resolution
   paths; it never falls back to `npx`). FAIL if neither resolves.
4. **Consumer markdownlint config** — search the whole repository tree, not just the root:
   the hook loads every config on the walk from an edited file's directory up to the repo
   root, so `docs/.markdownlint.cjs` applies to `docs/foo.md` even when the root has none.
   Find all `.markdownlint*` / `.markdownlint-cli2.*` files at any depth (skip
   `node_modules`), report the root config the default cascade discovers (or INFO that none
   exists — the tool's defaults then apply), list nested configs with their directory scope,
   and surface the README's configuration trust boundary using the hook's own risk criteria:
   any executable (`.cjs`/`.mjs`) config anywhere in the tree, AND any declarative
   `.markdownlint-cli2.*` file declaring `customRules`, `markdownItPlugins`, or
   `outputFormatters` — those keys load modules just like executable config.
5. **Hook toggle** — report the effective `markdown_format_enabled` value:
   `${user_config.markdown_format_enabled}` (unexpanded or empty means default `true`).
6. **Hook registration** — INFO: confirm the plugin is enabled for this project
   (`/plugin` → Installed) rather than parsing settings files.

## `apply` (idempotent)

Run `check`, then for each FAIL offer the resolution — never install anything without the
consumer's explicit go-ahead in the invocation. `apply install-lint` adds
`markdownlint-cli2` as a dev dependency in the consumer repository **using the
repository's own package manager**, resolved in order: lockfile (`pnpm-lock.yaml` →
`pnpm add -D`, `yarn.lock` → `yarn add -D`, `bun.lock`/`bun.lockb` → `bun add -d`,
`package-lock.json` → `npm install --save-dev`), then the `package.json`
`"packageManager"` field when no lockfile exists, then npm only when neither signal is
present. With no `package.json`, an ambiguous multi-lockfile state, or a lockfile that
contradicts `packageManager`, stop with manager-specific guidance instead of guessing —
never introduce a competing lockfile. The change is stated before running. For everything
else `apply` only points:

- missing `jq` / Bash: platform install instructions from the README Requirements section;
  this skill never installs system packages.
- toggle off: direct to `/plugin configure markdown-format` or
  `claude plugin install markdown-format@<marketplace> --config markdown_format_enabled=true`;
  this skill never writes user settings or `pluginConfigs`.
- no markdownlint config: offer to create a minimal `.markdownlint-cli2.jsonc` in the
  repository root only when explicitly asked — the plugin imposes no rules of its own.

Re-running `apply` after everything passes changes nothing and reports "already configured".

## What this skill does NOT do

- Run the formatter — editing any `.md` file exercises the hook end-to-end.
- Write the plugin cache, Claude Code user settings, or `pluginConfigs`.
- Download or execute tools during `check`; network use happens only in an explicitly
  requested `apply install-lint` inside the consumer repository.
