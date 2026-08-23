---
description: "Verify the markdown-format hook's runtime prerequisites and configuration for this repository. Use when: 'set up markdown-format', 'configure markdown-format', 'is markdown-format working', formatting silently isn't happening, or the hook reported a missing prerequisite. Actions: check (read-only verification, default) | apply (resolve what check found). Re-runnable and safe."
argument-hint: "check | apply [install-lint]"
user-invocable: true
disable-model-invocation: true
---

## Purpose

Thin check-centric setup per the uniform setup contract (`docs/PLUGIN-PHILOSOPHY.md`
"Setup is explicit and repeatable" in the marketplace repository): `check` inspects and
reports, `apply` resolves. This plugin owns no consumer-project configuration — rules
come from the repository's own markdownlint config, and the only tunable is the native
`userConfig` toggle — so `apply` is guidance-and-verify, with exactly one write path:
the explicitly invoked `apply install-lint` dependency install described below.

Action routing: no argument or `check` runs the check; `apply` runs the check first, then
remediation; `apply install-lint` additionally authorizes the consumer-repo dependency
install described below. All are non-interactive — never prompt when the action is given.

## `check` (read-only)

The hook script (`${CLAUDE_PLUGIN_ROOT}/hooks/markdown-format.sh`) is the single source of
truth for what it requires and how it resolves things.

**Read it first** — probe what it actually does, don't recite this file. Then run each probe via
Bash and report a PASS/FAIL/INFO table with one remediation line per FAIL. Do not modify anything.

When the plugin's toggle is disabled, every prerequisite absence downgrades from FAIL to
INFO — the hook exits through its enabled-gate before probing anything, so a deliberately
disabled plugin is not broken. Report the probes informationally and note that re-enabling
restores the FAIL semantics.

1. **Bash version** — check against the hook's documented floor (README Requirements),
   noting any features the hook degrades without (for example telemetry's Bash builtin).
2. **`jq`** — `command -v jq`. FAIL if absent *and* the repository opted in per item 4: the
   hook then skips with a visible once-per-session notice instead of formatting. Without
   that opt-in the hook decides the opt-in first and emits nothing at all, so report jq's
   absence as INFO there — the missing config, not jq, is why nothing happens.
3. **`markdownlint-cli2`** — resolve it exactly the way the hook's resolution code does
   (its sanctioned lookup paths, including its symlink/escape validation of a repo-local
   shim). A binary or shim the hook would reject must not PASS here. Then confirm the
   resolved tool actually executes — run it with `--version` (a repo shim can resolve yet
   still be broken: missing Node interpreter, dangling target); resolution without
   successful execution is FAIL, with the execution error in the remediation line. FAIL
   when nothing the hook would accept resolves.
4. **Consumer markdownlint config — the opt-in** — this is what activates the hook, not a
   style detail. Mirror its walk: from an edited file's directory up to the repo root, so
   nested configs apply to nested files and the opt-in is per-path (a root config covers
   the tree; a `docs/` config covers only `docs/`). Where that walk finds nothing the hook
   exits silently — no `--fix`, no findings, and no notice of any kind, not even a missing
   prerequisite. Search the whole tree (skip `node_modules`), report the root config the
   cascade discovers, list nested configs with their directory scope, and surface the
   README's configuration trust boundary for every config the hook's own risk collection
   (`collect_risky_configs`) would flag. For a path no config governs, report the hook as
   **INFO — inactive, not PASS**: nothing is broken, the repository simply never opted in,
   and that is the whole reason formatting is not happening. Name the remediation in the
   same line rather than leaving the reader to infer it. Never report markdownlint's own
   default rules as the fallback — an unconfigured repo gets no rules, not the defaults.
5. **Path scope — the repository's `.gitignore`** — INFO: the hook leaves a gitignored
   file alone, neither rewriting nor reporting on it, because a path the repository
   excludes is not part of the reviewable artifact. List the ignored Markdown the
   repository carries as out of scope — `git ls-files --others --ignored
   --exclude-standard -- '*.md' '*.mdc'` — and note that a tracked file is never treated
   as ignored even when a pattern matches it. Report the effective
   `${user_config.markdown_format_lint_gitignored}` value (unexpanded or empty means
   default `false`, i.e. gitignored files are skipped); `true` restores linting there.
6. **Hook toggle** — report the effective `markdown_format_enabled` value:
   `${user_config.markdown_format_enabled}` (unexpanded or empty means default `true`).
7. **Hook registration** — INFO: confirm the plugin is enabled for this project
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
- toggle off: direct to `/plugin configure markdown-format` (interactive, any
  time). Headless: rerun the install with the new value —
  `claude plugin install markdown-format@<marketplace> -s <scope> --config markdown_format_enabled=true`
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
- no markdownlint config: this is why the hook does nothing here, so lead with it rather
  than leaving it as a footnote under the passing prerequisites. Then offer to create a
  minimal `.markdownlint-cli2.jsonc` in the repository root only when explicitly asked —
  the plugin imposes no rules of its own, and which rules a repository adopts is its own
  decision, never this skill's.

Re-running `apply` after everything passes changes nothing and reports "already configured".

## What this skill does NOT do

- Run the formatter — editing any `.md` file exercises the hook end-to-end. The only
  execution `check` performs is the harmless `--version` liveness probe of the resolved
  linter; it never lints, fixes, or touches repository content.
- Write the plugin cache, Claude Code user settings, or `pluginConfigs`.
- Download anything during `check`; network use happens only in an explicitly
  requested `apply install-lint` inside the consumer repository.
