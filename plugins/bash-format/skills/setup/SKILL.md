---
description: "Verify the bash-format hook's runtime prerequisites and configuration for this repository. Use when: 'set up bash-format', 'configure bash-format', 'is bash-format working', shell lint or formatting silently isn't happening, or the hook reported a missing prerequisite. Actions: check (read-only verification, default) | apply (resolve what check found). Re-runnable and safe."
argument-hint: "check | apply"
user-invocable: true
disable-model-invocation: true
shell: bash
---

## Pre-computed context

`check`'s tool probes ran at load time. Read these rows instead of re-issuing them; each shows the
tool's path when present, or `absent` when missing:

- `jq`: !`{ command -v jq 2>/dev/null || echo "absent"; }`
- `node`: !`{ command -v node 2>/dev/null || echo "absent"; }`
- `shellcheck`: !`{ command -v shellcheck 2>/dev/null || echo "absent"; }`
- `shfmt`: !`{ command -v shfmt 2>/dev/null || echo "absent"; }`

A row reading `[shell command execution disabled by policy]` carries no result: run that tool's
`command -v` probe via Bash instead.

## Purpose

Thin check-centric setup per the uniform setup contract (`docs/plugin-philosophy.md`
"Setup is explicit and repeatable" in the marketplace repository): `check` inspects and
reports, `apply` resolves. This plugin owns no consumer-project configuration. Linting
rules come from the repository's own `.shellcheckrc`, formatting from its `.editorconfig`,
and the only tunables are the native `userConfig` options `bash_format_enabled` and
`bash_format_lint_gitignored`. Every prerequisite is a `PATH`
binary the plugin never bundles, and the plugin never installs system packages, so `apply`
is guidance-only with **no write path**. It never modifies the repository, user settings, or
the plugin cache.

Action routing: no argument or `check` runs the check; `apply` runs the check first, then
offers remediation guidance. Both are non-interactive. Never prompt when the action is given.

## `check` (read-only)

The hook script (`${CLAUDE_PLUGIN_ROOT}/hooks/bash-format.sh`) is the single source of truth
for what it requires and how it resolves things.

**Read it first.** Probe what it actually does, don't recite this file. Then read the
pre-computed tool rows, run the remaining probes via Bash, and report a PASS/FAIL/INFO
table with one remediation line per FAIL. Do not modify anything.

The lint pass and the format pass are independent; report each separately. The `jq` skip notice
appears once per session and agent; the `shellcheck` and `shfmt` notices appear once per session,
shared by all agents. Each renews every eighth skip (README Requirements).

When the plugin's toggle is disabled, every prerequisite absence downgrades from FAIL to
INFO. The hook exits through its enabled-gate before probing anything, so a deliberately
disabled plugin is not broken. Report the probes informationally and note that re-enabling
restores the FAIL semantics.

1. **Bash version.** Check against the hook's documented floor (README Requirements),
   noting any features the hook degrades without (for example telemetry's `EPOCHREALTIME`,
   a Bash 5.0+ builtin).
2. **`node`.** The pre-computed `node` row. FAIL if absent: every hook row launches through
   `node hooks/exec-bash.mjs`, so without `node` the hook does not launch and no shell edit is
   linted or formatted (README Requirements).
3. **`jq`.** The pre-computed `jq` row. FAIL if absent: the hook then skips with a visible
   notice instead of running either pass.
4. **`shellcheck`** (lint pass). The pre-computed `shellcheck` row. FAIL if absent: the lint pass
   skips with a visible notice.
5. **`shfmt`** (format pass). The pre-computed `shfmt` row. Its FAIL/INFO status depends on the
   `.editorconfig` opt-in below, because the format pass runs **only when the repo has opted
   in**:
   - opted in AND `shfmt` absent → FAIL: the format pass skips with a visible
     notice.
   - not opted in → INFO regardless of `shfmt`: the format pass stays quiet by design (the
     repo chose not to format), so a missing `shfmt` is not a defect here.
6. **`.editorconfig` shell opt-in.** Mirror the hook's opt-in logic
   (`shell_editorconfig_opt_in` / `section_applies_to_shell`), not merely "does an
   `.editorconfig` exist". The opt-in is an EditorConfig **section that names shell files**:
   a shell glob such as `[*.sh]`, `[*.bash]`, or `[*.{sh,bash}]` (including path-prefixed
   forms like `[**/*.sh]`), discovered by walking up from the file's directory to the repo
   root and stopping at a `root = true` config. A bare `[*]` catch-all does NOT count (most
   repos only set line-ending / charset properties there). Path-only sections like
   `[scripts/**]` do NOT count either. Report as INFO: whether a governing shell section
   exists and therefore whether the format pass is active. If none exists, INFO-note the
   consequence per the hook's logic: shell files are left unformatted rather than rewritten
   to shfmt's built-in defaults.
7. **`.shellcheckrc`.** INFO: ShellCheck auto-discovers `.shellcheckrc` by walking up from
   the file's directory. Report whether one exists; its absence is not a FAIL (ShellCheck
   applies its own defaults).
8. **Hook options.** Report both effective values. `${user_config.bash_format_enabled}`
   (unexpanded or empty means the manifest default `true`; any value other than `true`
   disables the hook). `${user_config.bash_format_lint_gitignored}` (unexpanded or empty means
   the manifest default `false`): unless it is `true`, an edit to a file the repository
   gitignores is silently skipped, so a user asking why `.work/scratch.sh` was not formatted
   gets this answer.
9. **Hook registration.** INFO: confirm the plugin is enabled for this project
   (`/plugin` → Installed) rather than parsing settings files.
10. **Project scope.** INFO: when `CLAUDE_PROJECT_DIR` is set, the hook acts only
   on shell files inside it (symlink-resolved membership guard in the shared hook
   library, aware of Windows 8.3 short-name spellings of in-project paths, a
   per-volume property; only volumes with 8.3 generation enabled produce them);
   a `.sh`/`.bash` file written *outside* the project (temp/scratchpad
   dirs) is silently skipped. No lint, no format, no notice. The OS temp tree
   counts as outside even when it sits under `CLAUDE_PROJECT_DIR`, unless the
   project root itself lives under temp. When
   `CLAUDE_PROJECT_DIR` is **unset** (e.g. some headless `-p` sessions) the guard
   is skipped and any existing edited file is processed. Report this so a green
   `check` is not read as "every shell edit anywhere is covered".
11. **Gitignored files.** INFO: unless `bash_format_lint_gitignored` is `true`, a file the
    repository gitignores (`git check-ignore`) is silently skipped: no lint, no format, no
    notice. A tracked file that matches an ignore pattern stays in scope, and when git cannot
    decide (git absent, no repository, an error) the hook acts as before
    (`hook::gitignored_out_of_scope` in `hooks/rewrite-guard.sh`). Report the item 8 value
    beside this.

When every probe passes, report the result **with the scope caveats** (items 10 and 11).
Never an unqualified "fully operational", which would imply out-of-project shell
edits are covered when they are deliberately skipped.

## `apply` (idempotent)

Run `check`, then for each FAIL point at the resolution. This skill installs nothing:

- missing `shellcheck`: install guidance from the README Requirements section
  (the [ShellCheck install guide](https://github.com/koalaman/shellcheck#installing)); this
  skill never installs system packages.
- missing `shfmt` while the repo opts in: install guidance
  ([shfmt](https://github.com/mvdan/sh#shfmt)); this skill never installs system packages.
- missing `node` / `jq` / Bash: platform install instructions from the README Requirements section.
- no shell `.editorconfig` opt-in (and formatting is wanted): explain that adding a governing
  shell section (`[*.sh]`, `[*.bash]`, or `[*.{sh,bash}]`) to an `.editorconfig` opts the
  repo in. A bare `[*]` is not enough, but this skill does not write it. `.editorconfig` is
  cross-cutting (it governs every editor and tool in the repo), so the choice and the edit
  belong to the consumer.
- toggle off, or gitignored files wanted: reconfigure through Claude Code's native flow, per the marketplace's
  plugin-reconfiguration convention
  (<https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/plugin-reconfiguration/README.md>,
  which owns the verified-version record): interactive
  `/plugin configure bash-format@<marketplace>` any time, or headless
  `claude plugin install bash-format@<marketplace> -s <scope> --config bash_format_enabled=true`
  (or `--config bash_format_lint_gitignored=true`; repeatable per key). Against an already-installed plugin it prints `already installed`
  **and still writes the value**. Do **not** uninstall to reconfigure: that drops this plugin's
  entire stored `pluginConfigs` entry, resetting every option in the README's Options reference
  to its manifest default. `-s` defaults to `user`; pass the scope `claude plugin list` reports
  for this plugin, and run from that project's directory for a `project`/`local` scope, or the
  rerun adds a second install record at the scope passed and enables the plugin there; the
  value itself always lands in user settings. A rejected value prints a warning yet exits 0,
  so read the output. This skill never writes user settings or
  `pluginConfigs`. Afterwards rerun `check` in a **fresh session**. The rendered
  `${user_config.*}` is injected at skill load and each hook receives its
  `CLAUDE_PLUGIN_OPTION_*` from an environment fixed at session start, so a same-session
  `check` still reports the OLD value; report the observed effective value, never an
  unobserved change.

After pointing at a remediation, re-run the relevant `check` probe live via Bash (a pre-computed row
predates the remediation, so never re-read it) and report its actual result. Never claim resolved on
the reader's report that they installed something.

Re-running `apply` after everything passes changes nothing and reports "already configured".

## What this skill does NOT do

- Run the linter or formatter. Editing any `.sh` or `.bash` file exercises the hook
  end-to-end.
- Write the plugin cache, Claude Code user settings, or `pluginConfigs`. Nor the repository,
  including `.editorconfig` / `.shellcheckrc`. Every prerequisite is a `PATH` binary or the
  native toggle, so remediation is guidance only.
- Download or execute tools during `check` beyond the read-only `command -v` presence probes.

## Gotchas

- **`ENAMETOOLONG` when grepping the plugin cache.** Installed plugins run from a
  deeply nested, cache-isolated path. Piping a `grep`/`rg` over the long absolute
  path to `hooks/hook-utils.sh` (or another bundled file) can spawn-fail with
  `ENAMETOOLONG` on some hosts. Read the file directly (or `cd` into the plugin
  hooks dir first and grep a short relative path) rather than passing the full
  cache path on the command line.
- **`check` PASS ≠ every shell edit is covered.** When `CLAUDE_PROJECT_DIR` is set
  the hook is project-scoped (probe 10): shell files written outside it are silently
  skipped, so a fully green `check` still does not cover out-of-project edits. (When
  `CLAUDE_PROJECT_DIR` is unset the scoping does not apply. See probe 10.)
- **`shfmt` FAIL is opt-in-conditional.** A missing `shfmt` is only a FAIL when an
  `.editorconfig` section governs shell files; without that opt-in it is INFO, not
  a defect. Resolve the `.editorconfig` opt-in state before calling `shfmt` a failure.
