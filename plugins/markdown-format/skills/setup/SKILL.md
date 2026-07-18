---
name: setup
description: "Verify the markdown-format hook's runtime prerequisites and configuration for this repository. Use when: 'set up markdown-format', 'configure markdown-format', 'is markdown-format working', formatting silently isn't happening, or the hook reported a missing prerequisite. Actions: check (read-only verification, default) | apply (resolve what check found). Re-runnable and safe."
argument-hint: "check | apply [install-lint]"
user-invocable: true
disable-model-invocation: true
---

## Purpose

Thin check-centric setup per the uniform contract: `check` inspects and reports, `apply`
resolves. This plugin owns no consumer-project configuration — rules come from the
repository's own markdownlint config, and the only tunable is the native `userConfig`
toggle — so `apply` is guidance-and-verify, with exactly one write path: the explicitly
invoked `apply install-lint` dependency install described below.

Action routing: no argument or `check` runs the check; `apply` runs the check first, then
remediation; `apply install-lint` additionally authorizes the consumer-repo dependency
install described below. All are non-interactive — never prompt when the action is given.

## `check` (read-only)

The hook script (`${CLAUDE_PLUGIN_ROOT}/hooks/markdown-format.sh`) is the single source of
truth for what it requires and how it resolves things. **Read it first** — probe what it
actually does, don't recite this file. Then run each probe via Bash and report a
PASS/FAIL/INFO table with one remediation line per FAIL. Do not modify anything.

1. **Bash version** — check against the hook's documented floor (README Requirements),
   noting any features the hook degrades without (for example telemetry's Bash builtin).
2. **`jq`** — `command -v jq`. FAIL if absent: the hook then skips with a visible
   once-per-session notice instead of formatting.
3. **`markdownlint-cli2`** — resolve it exactly the way the hook's resolution code does
   (its sanctioned lookup paths, including its symlink/escape validation of a repo-local
   shim). A binary or shim the hook would reject must not PASS here. FAIL when nothing the
   hook would accept resolves.
4. **Consumer markdownlint config** — mirror the hook's config walk: it loads configs from
   an edited file's directory up to the repo root, so nested configs apply to nested files.
   Search the whole tree (skip `node_modules`), report the root config the cascade
   discovers (or INFO that none exists — tool defaults then apply), list nested configs
   with their directory scope, and surface the README's configuration trust boundary for
   every config the hook's own risk collection (`collect_risky_configs`) would flag.
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
`package-lock.json` or `npm-shrinkwrap.json` → `npm install --save-dev`), then the
`package.json` `"packageManager"` field when no lockfile exists, then npm only when
neither signal is present. With no `package.json`, an ambiguous multi-lockfile state, or a lockfile that
contradicts `packageManager`, stop with manager-specific guidance instead of guessing —
never introduce a competing lockfile. The change is stated before running. For a Yarn repository, don't infer the linker — ask
the repo's own Yarn: run `yarn config get nodeLinker` in the repo. `pnp` (Berry's default
when unset) → skip the install and give guidance, because Plug'n'Play generates a loader file,
not the `node_modules/.bin` shim the hook resolves; install `markdownlint-cli2` on
`PATH` or switch the linker. `node-modules`/`pnpm`, or Yarn Classic (which has no such
setting and always materializes `node_modules`) → install. The
verify-after-remediation rule below is the backstop when an install still yields no
usable shim. After ANY remediation, re-run the
relevant `check` probe and report its actual result — never claim resolved on the
install command's exit code alone. For everything else `apply` only points:

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
