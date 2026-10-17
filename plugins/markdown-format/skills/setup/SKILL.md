---
description: "Verify markdown-format's prerequisites and configuration here, and register its git pre-commit entry. Use when: 'set up markdown-format', 'configure markdown-format', 'is markdown-format working', formatting silently isn't happening, or a hook reported a missing prerequisite or drifted git hook. Actions: check (read-only, default) | apply [install-lint] | apply install-git-hooks [scope=local|shared]. Re-runnable."
argument-hint: "[check|apply [install-lint|install-git-hooks [scope=local|shared]]]"
user-invocable: true
disable-model-invocation: true
allowed-tools:
  - "Bash(command -v jq*)"
  - "Bash(node \"${CLAUDE_PLUGIN_ROOT}/lib/git-hooks/install.mjs\" verify:*)"
  - "Bash(node ${CLAUDE_PLUGIN_ROOT}/lib/git-hooks/install.mjs verify:*)"
  - "Bash(node \"${CLAUDE_PLUGIN_ROOT}/lib/git-hooks/install.mjs\" plan:*)"
  - "Bash(node ${CLAUDE_PLUGIN_ROOT}/lib/git-hooks/install.mjs plan:*)"
shell: bash
---

## Pre-computed context

`check`'s `jq` probe ran at load time. Read this row instead of re-issuing it; it shows
the tool's path when present, or `absent` when missing:

- `jq`: !`command -v jq 2>/dev/null || echo absent`

A row missing, reading as literal command text (the skill was reached through
`/markdown-format:check`, where this line never runs), or reading `[shell command execution
disabled by policy]` carries no result: run that tool's `command -v` probe via Bash instead.

## Purpose

Thin check-centric setup per the uniform setup contract (`docs/plugin-philosophy.md`
"Setup is explicit and repeatable" in the marketplace repository): `check` inspects and
reports, `apply` resolves. The only consumer-project files this plugin owns are its git-hook
entry copies, which `apply install-git-hooks` writes. Rules come from the repository's own
markdownlint config, and the tunables are the native `userConfig` options (the on/off toggle,
the gitignored-file switch and the end-of-turn check). `apply` is otherwise guidance-and-verify,
with one more write path: the explicitly invoked `apply install-lint` dependency install
described below.

Action routing: no argument or `check` runs the check; `apply` runs the check first, then
remediation; `apply install-lint` additionally authorizes the consumer-repo dependency
install described below. All are non-interactive. Never prompt when the action is given.
`apply install-git-hooks` asks only where its section says to.

## `check` (read-only)

The hook script (`${CLAUDE_PLUGIN_ROOT}/hooks/markdown-format.sh`) and the gates it shares with
the pre-commit entry (`${CLAUDE_PLUGIN_ROOT}/git-hooks/markdown-gates.sh`) are the single source
of truth for what the plugin requires and how it resolves things.

**Read them first.** Probe what they actually do, don't recite this file. Then read the
pre-computed `jq` row, run the remaining probes via Bash, and report a PASS/FAIL/INFO
table with one remediation line per FAIL. Do not modify anything.

When the plugin's toggle is disabled, every prerequisite absence except Node.js (item 1)
downgrades from FAIL to INFO. The hook and the `SessionStart` probe both exit through the
enabled gate before probing anything, so a deliberately disabled plugin is not broken.
Node.js stays FAIL: Claude Code must spawn `node` for the hook row before that gate can run.
Report the probes informationally and note that re-enabling restores the FAIL semantics.

1. **Node.js.** Every hook row starts through `node hooks/exec-bash.mjs`, so without
   `node` on `PATH` no hook launches and nothing is enforced. Probe it via Bash with
   `node --version` (a hook cannot report its own missing launcher; a stale version-manager
   shim resolves on `PATH` yet cannot run, so resolution alone is not a PASS). FAIL if it is
   absent or exits non-zero, in every toggle state; the remediation is to install or repair
   Node.js (README Requirements).
2. **Bash version.** Check against the hook's documented floor (README Requirements).
3. **`jq`.** The pre-computed `jq` row, or the Bash probe when that row carries no result. The
   batch hook reads the file paths with `jq` and does nothing, silently, without it. FAIL if
   absent *and* the repository opted in per item 5; INFO otherwise, because without a config
   nothing would run anyway and the missing config, not jq, is why.
4. **`markdownlint-cli2`.** Resolve it exactly the way the gates' `md_local_bin` and the
   hook's PATH lookup do: `PATH` first, then `node_modules/.bin/markdownlint-cli2` walking up
   from a Markdown file's directory to the repository root, with the shim's symlinks followed
   and its physical target required to stay inside the repository's `node_modules` tree. A
   binary or shim the hook would reject must not PASS here. Then confirm the resolved tool
   actually executes. Run it with `--version` (a repo shim can resolve yet still be broken:
   missing Node interpreter, dangling target); resolution without successful execution is
   FAIL, with the execution error in the remediation line. FAIL when nothing the hook would
   accept resolves.
5. **Consumer markdownlint config, the opt-in.** This is what activates the plugin, not a
   style detail. Mirror the gates' `md_config_state` walk: from a Markdown file's directory
   up to the repo root, so nested configs apply to nested files and the opt-in is per-path (a
   root config covers the tree; a `docs/` config covers only `docs/`). Where that walk finds
   nothing the hook exits silently: no `--fix`, no findings, and no notice, not even a missing
   prerequisite. The `SessionStart` probe does not check for a config, so it can still report
   a missing `markdownlint-cli2` in a repository that never opted in. Search the whole tree
   (skip `node_modules`), report the root config the cascade discovers, list nested configs
   with their directory scope, and report as INFO, gated, every config the gates'
   `md_classify` flags (a `.cjs` or `.mjs` config, or one naming `customRules`,
   `markdownItPlugins` or `outputFormatters`, or holding a backslash in a quoted string): the
   plugin runs markdownlint-cli2 under it only after the user approves that config state
   (README "Trust model"), so until then the files it governs are neither rewritten nor
   checked. Never create the approval marker yourself: approval is the user's. For a path no config governs, report the plugin as **INFO,
   inactive, not PASS**: nothing is broken, the repository simply never opted in, and that is
   the whole reason formatting is not happening. Name the remediation in the same line rather
   than leaving the reader to infer it. Never report markdownlint's own default rules as the
   fallback. An unconfigured repo gets no rules, not the defaults.
6. **Path scope, the repository's `.gitignore`.** INFO: the batch hook leaves a gitignored
   file alone, because a path the repository excludes is not part of the reviewable artifact.
   (The pre-commit entry only sees files git stages, so it needs no such rule.) List the
   ignored Markdown the repository carries as out of scope with
   `git ls-files --others --ignored --exclude-standard -- '*.md' '*.mdc'`,
   and note that a tracked file is never treated
   as ignored even when a pattern matches it. Report the effective
   `${user_config.markdown_format_lint_gitignored}` value (unexpanded or empty means
   default `false`, i.e. gitignored files are skipped); `true` restores rewriting there.
7. **Hook toggle.** Report the effective `markdown_format_enabled` value:
   `${user_config.markdown_format_enabled}` (unexpanded or empty means default `true`). Also
   report `markdown_format_end_of_turn`: `${user_config.markdown_format_end_of_turn}`
   (unexpanded or empty means the shipped default `false`), as INFO: on, the Stop row checks
   the uncommitted changes once per turn; off, only the batch rewrite and the git pre-commit
   entry run.
8. **Hook registration.** INFO: confirm the plugin is enabled for this project
   (`/plugin` → Installed) rather than parsing settings files.
9. **Git pre-commit entry.** Run `node "${CLAUDE_PLUGIN_ROOT}/lib/git-hooks/install.mjs" verify`
   from the repository. Each line is `<state>\t<entry>[\t<detail>]`: `ok` is PASS, `declined` is
   INFO (this clone said no; silent at session start), and `missing`, `stale` or `modified` is a
   FAIL whose remediation is `apply install-git-hooks`. A `tool\t<tool>\tmissing` line means the
   installed entry cannot run here: list every such tool with its install method from the
   plugin's `prerequisites.json`, so a lane or cloud setup script can provision it before an
   auto-mode session commits. Outside a git repository, report INFO and skip the step.

## `apply install-git-hooks [scope=local|shared]`

Registers the plugin's git-hook entries (`git-hooks/entries.json`) with the repository's hook
manager. The installer script only detects, renders and writes files the plugin owns; every step
that needs judgment comes back to you as a `decisions[]` item, which you reason about and apply
with your own edit tools.

1. **Scope.** Use the argument when given. Otherwise, when the user is present, ask: `local`
   (this clone only, nothing committed) or `shared` (committed under `.githooks/markdown-format/`,
   so every teammate and agent gets it). When nobody can answer, use `local`.
2. **Plan.** Run `node "${CLAUDE_PLUGIN_ROOT}/lib/git-hooks/install.mjs" plan --scope <scope>`
   and read the JSON: `manager`, `actions[]`, `decisions[]`.
3. **Manager conflict.** A `manager-conflict` decision lists the evidence (two managers, or one
   this installer does not drive, such as the pre-commit framework). Show it and ask which manager
   should carry the entry; rerun `plan` with `--manager lefthook|husky|plain`. Without an answer,
   stop here and report.
4. **Actions.** When `actions[]` holds `copy` items, run
   `node "${CLAUDE_PLUGIN_ROOT}/lib/git-hooks/install.mjs" copy --scope <scope>` (plus the same
   `--manager` when you passed one). It prints `installed`, `refreshed`, `unchanged`, `refused` or
   `blocked` per entry; `refused` means a locally edited copy, which the `modified` decision
   covers, and `blocked` means another tool owns the local hooks directory, which the
   `hooks-path-owned` decision covers.
5. **Decisions.** Read [reference/git-hook-decisions.md](reference/git-hook-decisions.md) for
   what each kind asks of you, apply each one, then rerun `plan` until only the decisions you
   chose to leave remain.
6. **Verify.** Run `verify` and report its lines as `check` step 9 does.

The entry rewrites: at commit it formats the staged Markdown files and stages the result, so tell
the user that a commit can change the files it contains, and that a partly staged Markdown file is
refused untouched.

When the user does not want an entry in this clone, run
`node "${CLAUDE_PLUGIN_ROOT}/lib/git-hooks/install.mjs" decline --entry markdown-check`; the
session-start drift line then stays silent until `verify` runs by hand, and `--undo` reverses it.
Add `--global` (with or without `--undo`) to decline the entry in every clone;
`git config --global checks.git-hooks.declined true` declines every entry of every plugin, and an
entry's own key set to `false` in a clone opts that entry back in.

## `apply` (idempotent)

Run `check`, then for each FAIL offer the resolution. Never install anything without the
consumer's explicit go-ahead in the invocation. `apply install-lint` adds
`markdownlint-cli2` as a dev dependency in the consumer repository **using the
repository's own package manager**, resolved in order: lockfile (`pnpm-lock.yaml` →
`pnpm add -D`, `yarn.lock` → `yarn add -D`, `bun.lock`/`bun.lockb` → `bun add -d`,
`package-lock.json` or `npm-shrinkwrap.json` → `npm install --save-dev`), then the
`package.json` `"packageManager"` field when no lockfile exists, then npm only when
neither signal is present. With no `package.json`, an ambiguous multi-lockfile state, or a lockfile that
contradicts `packageManager`, stop with manager-specific guidance instead of guessing.
Never introduce a competing lockfile. The change is stated before running. For a Yarn repository, don't infer the linker. Ask
the repo's own Yarn: run `yarn config get nodeLinker` in the repo. `pnp` (Berry's default
when unset) → skip the install and give guidance, because Plug'n'Play generates a loader file,
not the `node_modules/.bin` shim the hook resolves; install `markdownlint-cli2` on
`PATH` or switch the linker. `node-modules`/`pnpm`, or Yarn Classic (which has no such
setting and always materializes `node_modules`) → install. The
verify-after-remediation rule below is the backstop when an install still yields no
usable shim. After ANY remediation, re-run the
relevant `check` probe live via Bash (a pre-computed row predates the remediation) and report
its actual result. Never claim resolved on the
install command's exit code alone. For everything else `apply` only points:

- missing `jq` / Bash / Node.js: platform install instructions from the README Requirements section;
  this skill never installs system packages.
- toggle off: reconfigure through Claude Code's native flow, per the marketplace's
  plugin-reconfiguration convention
  (<https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/plugin-reconfiguration/README.md>,
  which owns the verified-version record): interactive `/plugin configure markdown-format@<marketplace>`
  any time, or headless
  `claude plugin install markdown-format@<marketplace> -s <scope> --config markdown_format_enabled=true`
  (repeatable per key). Against an already-installed plugin it prints `already installed` and
  still writes the value. Do **not** uninstall to reconfigure: that drops the plugin's entire
  stored `pluginConfigs` entry, resetting every option in the README's Options reference to its
  manifest default. Pass the scope `claude plugin list` reports for this plugin, and for a
  `project` or `local` scope run from that project's directory, so the rerun matches the existing
  install record; from the home directory pass `user`. A rejected value prints a warning yet
  exits 0, so read the output. This skill never writes user settings or `pluginConfigs`. Afterwards rerun
  `check` in a **fresh session**. The rendered `${user_config.*}` and the hook's
  `CLAUDE_PLUGIN_OPTION_*` are fixed at session start, so a same-session `check` still reports
  the OLD value; report the observed effective value, never an unobserved change.
- no markdownlint config: this is why the plugin does nothing here, so lead with it rather
  than leaving it as a footnote under the passing prerequisites. Then offer to create a
  minimal `.markdownlint-cli2.jsonc` in the repository root only when explicitly asked.
  The plugin imposes no rules of its own, and which rules a repository adopts is its own
  decision, never this skill's.

Re-running `apply` after everything passes changes nothing and reports "already configured".

## What this skill does NOT do

- Run the formatter. Editing any `.md` file exercises the batch hook end-to-end, and
  `git commit` exercises the installed pre-commit entry. The only
  execution `check` performs is the harmless `--version` liveness probe of the resolved
  linter; it never lints, fixes, or touches repository content.
- Write the plugin cache, Claude Code user settings, or `pluginConfigs`.
- Download anything during `check`; network use happens only in an explicitly
  requested `apply install-lint` inside the consumer repository.
