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
4. **Consumer markdownlint config** — from the repository root, report which config file
   `markdownlint-cli2` will discover (`.markdownlint-cli2.jsonc`, `.markdownlint.json`, …)
   or INFO that none exists (the tool's defaults then apply). If the discovered config is
   executable (`.cjs`/`.mjs`), surface the README's configuration trust boundary.
5. **Hook toggle** — report the effective `markdown_format_enabled` value:
   `${user_config.markdown_format_enabled}` (unexpanded or empty means default `true`).
6. **Hook registration** — INFO: confirm the plugin is enabled for this project
   (`/plugin` → Installed) rather than parsing settings files.

## `apply` (idempotent)

Run `check`, then for each FAIL offer the resolution — never install anything without the
consumer's explicit go-ahead in the invocation (e.g. `apply install-lint` may run
`npm install --save-dev markdownlint-cli2` in the consumer repository when a
`package.json` exists; that is a consumer-repo dependency change and is stated before
running). For everything else `apply` only points:

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
