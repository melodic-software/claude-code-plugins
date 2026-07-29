---
name: setup
description: "Verify the bash-format hook's runtime prerequisites and configuration for this repository. Use when: 'set up bash-format', 'configure bash-format', 'is bash-format working', shell lint or formatting silently isn't happening, or the hook reported a missing prerequisite. Actions: check (read-only verification, default) | apply (resolve what check found). Re-runnable and safe."
argument-hint: "check | apply"
user-invocable: true
disable-model-invocation: true
---

## Purpose

Thin check-centric setup per the uniform contract: `check` inspects and reports, `apply`
resolves. This plugin owns no consumer-project configuration — linting rules come from the
repository's own `.shellcheckrc`, formatting from its `.editorconfig`, and the only tunable is
the native `userConfig` toggle. Every prerequisite is a `PATH` binary the plugin never
bundles, and the plugin never installs system packages, so `apply` is guidance-only with **no
write path** — it never modifies the repository, user settings, or the plugin cache.

Action routing: no argument or `check` runs the check; `apply` runs the check first, then
offers remediation guidance. Both are non-interactive — never prompt when the action is given.

## `check` (read-only)

The hook script (`${CLAUDE_PLUGIN_ROOT}/hooks/bash-format.sh`) is the single source of truth
for what it requires and how it resolves things. **Read it first** — probe what it actually
does, don't recite this file. The lint pass and the format pass are independent; report each
separately. Then run each probe via Bash and report a PASS/FAIL/INFO table with one
remediation line per FAIL. Do not modify anything.

When the plugin's toggle is disabled, every prerequisite absence downgrades from FAIL to
INFO — the hook exits through its enabled-gate before probing anything, so a deliberately
disabled plugin is not broken. Report the probes informationally and note that re-enabling
restores the FAIL semantics.

1. **Bash version** — check against the hook's documented floor (README Requirements),
   noting any features the hook degrades without (for example telemetry's `EPOCHREALTIME`,
   a Bash 5.0+ builtin).
2. **`jq`** — `command -v jq`. FAIL if absent: the hook then skips with a visible
   once-per-session notice instead of running either pass.
3. **`shellcheck`** (lint pass) — `command -v shellcheck`. FAIL if absent: the lint pass
   skips with a visible once-per-session notice.
4. **`shfmt`** (format pass) — `command -v shfmt`. Its FAIL/INFO status depends on the
   `.editorconfig` opt-in below, because the format pass runs **only when the repo has opted
   in**:
   - opted in AND `shfmt` absent → FAIL: the format pass skips with a visible once-per-session
     notice.
   - not opted in → INFO regardless of `shfmt`: the format pass stays quiet by design (the
     repo chose not to format), so a missing `shfmt` is not a defect here.
5. **`.editorconfig` shell opt-in** — mirror the hook's opt-in logic
   (`shell_editorconfig_opt_in` / `section_applies_to_shell`), not merely "does an
   `.editorconfig` exist". The opt-in is an EditorConfig **section that governs shell files**
   — a `[*]` catch-all or a shell glob such as `[*.sh]`, `[*.bash]`, or `[*.{sh,bash}]`
   (including path-prefixed forms like `[**/*.sh]`) — discovered by walking up from the file's
   directory to the repo root and stopping at a `root = true` config. Path-only sections like
   `[scripts/**]` do NOT count. Report as INFO: whether a governing shell section exists and
   therefore whether the format pass is active. If none exists, INFO-note the consequence per
   the hook's logic: shell files are left unformatted rather than rewritten to shfmt's
   built-in defaults.
6. **`.shellcheckrc`** — INFO: ShellCheck auto-discovers `.shellcheckrc` by walking up from
   the file's directory. Report whether one exists; its absence is not a FAIL (ShellCheck
   applies its own defaults).
7. **Hook toggle** — report the effective `bash_format_enabled` value:
   `${user_config.bash_format_enabled}` (unexpanded or empty means default `true`; any value
   other than `true` disables the hook).
8. **Hook registration** — INFO: confirm the plugin is enabled for this project
   (`/plugin` → Installed) rather than parsing settings files.
9. **Project scope** — INFO: when `CLAUDE_PROJECT_DIR` is set, the hook acts only
   on shell files inside it (symlink-resolved membership guard in the shared hook
   library, aware of Windows 8.3 short-name spellings of in-project paths — a
   per-volume property; only volumes with 8.3 generation enabled produce them);
   a `.sh`/`.bash` file written *outside* the project (temp/scratchpad
   dirs) is silently skipped — no lint, no format, no notice. When
   `CLAUDE_PROJECT_DIR` is **unset** (e.g. some headless `-p` sessions) the guard
   is skipped and any existing edited file is processed. Report this so a green
   `check` is not read as "every shell edit anywhere is covered".

When every probe passes, report the result **with the scope caveat** (item 9) —
never an unqualified "fully operational", which would imply out-of-project shell
edits are covered when they are deliberately skipped.

## `apply` (idempotent)

Run `check`, then for each FAIL point at the resolution — this skill installs nothing:

- missing `shellcheck`: install guidance from the README Requirements section
  (the [ShellCheck install guide](https://github.com/koalaman/shellcheck#installing)); this
  skill never installs system packages.
- missing `shfmt` while the repo opts in: install guidance
  ([shfmt](https://github.com/mvdan/sh#shfmt)); this skill never installs system packages.
- missing `jq` / Bash: platform install instructions from the README Requirements section.
- no shell `.editorconfig` opt-in (and formatting is wanted): explain that adding a governing
  shell section (`[*]`, `[*.sh]`, `[*.bash]`, or `[*.{sh,bash}]`) to an `.editorconfig` opts
  the repo in — but this skill does not write it. `.editorconfig` is cross-cutting (it governs
  every editor and tool in the repo), so the choice and the edit belong to the consumer.
- toggle off: direct to `/plugin configure bash-format` (interactive, any
  time). Headless: `--config` only applies on a fresh install (ignored once installed), so
  reconfigure via `claude plugin uninstall bash-format -s <scope>` then
  `claude plugin install bash-format@<marketplace> -s <scope> --config bash_format_enabled=true`;
  this skill never writes user settings or `pluginConfigs`. Both commands default to `-s user` —
  pass the scope `claude plugin list` reports for this plugin, and run from that project's
  directory for a `project`/`local` scope. Defaulting instead uninstalls a separate user-scope
  record while the effective install stays in place, so the reinstall lands at a scope that
  does not load.

After pointing at a remediation, re-run the relevant `check` probe and report its actual
result — never claim resolved on the reader's report that they installed something.

Re-running `apply` after everything passes changes nothing and reports "already configured".

## What this skill does NOT do

- Run the linter or formatter — editing any `.sh` or `.bash` file exercises the hook
  end-to-end.
- Write anything: not the repository (including `.editorconfig` / `.shellcheckrc`), not Claude
  Code user settings, not `pluginConfigs`, not the plugin cache. Every prerequisite is a `PATH`
  binary or the native toggle, so remediation is guidance only.
- Download or execute tools during `check` beyond the read-only `command -v` presence probes.

## Gotchas

- **`ENAMETOOLONG` when grepping the plugin cache.** Installed plugins run from a
  deeply nested, cache-isolated path. Piping a `grep`/`rg` over the long absolute
  path to `hooks/hook-utils.sh` (or another bundled file) can spawn-fail with
  `ENAMETOOLONG` on some hosts. Read the file directly (or `cd` into the plugin
  hooks dir first and grep a short relative path) rather than passing the full
  cache path on the command line.
- **`check` PASS ≠ every shell edit is covered.** When `CLAUDE_PROJECT_DIR` is set
  the hook is project-scoped (probe 9): shell files written outside it are silently
  skipped, so a fully green `check` still does not cover out-of-project edits. (When
  `CLAUDE_PROJECT_DIR` is unset the scoping does not apply — see probe 9.)
- **`shfmt` FAIL is opt-in-conditional.** A missing `shfmt` is only a FAIL when an
  `.editorconfig` section governs shell files; without that opt-in it is INFO, not
  a defect. Resolve the `.editorconfig` opt-in state before calling `shfmt` a failure.
