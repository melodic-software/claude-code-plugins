# bash-format

A Claude Code plugin that lints and formats shell scripts the moment you edit
them. On every `Write` or `Edit` of a `.sh` or `.bash` file it runs
[ShellCheck](https://www.shellcheck.net/) and (opt-in)
[shfmt](https://github.com/mvdan/sh), surfacing findings back to Claude as
advisory context.

It uses **your repository's own configuration** — `.shellcheckrc` for linting
and `.editorconfig` for formatting. It ships no rules of its own.

## Behavior

- **Lint on edit (always).** ShellCheck (`warning` severity and above) runs on
  every edit. It is non-mutating; it only reports.
- **Format on edit (opt-in).** `shfmt` runs **only when an `.editorconfig`
  section governs the edited shell file** — a `[*]` catch-all or a shell glob
  such as `[*.sh]`, `[*.bash]`, or `[*.{sh,bash}]`, found by walking up from the
  file to the repository root. A repo whose `.editorconfig` only configures other
  languages (or has none) leaves shell files untouched rather than rewriting them
  to shfmt's built-in defaults, so the plugin never imposes a style you did not
  choose. (Path-only sections like `[scripts/**]` are not treated as a shell
  opt-in; use a shell glob or `[*]`.) It runs with no parser/printer flags, so
  your `.editorconfig` is authoritative, and with `--apply-ignore` so an
  `ignore = true` section (e.g. for generated or vendored scripts) is honored
  even on a single edited file.
- **Advisory, never blocking.** The hook always exits `0`. Findings are reported
  via `additionalContext`; they never reject the edit. Make a commit hook or CI
  your hard gate.
- **Config from the consumer.** ShellCheck discovers `.shellcheckrc` by walking
  up from the file's directory; shfmt reads `.editorconfig` the same way. No
  working-directory assumptions — the tools are anchored to the edited file.
- **Scope: files inside the current project only.** The hook acts on shell files
  under `CLAUDE_PROJECT_DIR` (symlink-resolved). A `.sh`/`.bash` file written
  *outside* the project — e.g. to a temp or scratchpad directory — is silently
  skipped: no lint, no format, no notice. This is deliberate defense-in-depth
  scoping inherited from the shared hook library; if you need such a file linted,
  run `shellcheck` on it directly.

## Requirements

- **Bash** — the hook is a Bash script. On native Windows, install
  [Git for Windows](https://code.claude.com/docs/en/setup#set-up-on-windows) so
  Claude Code can run it under Git Bash.
- **jq** on `PATH` — parses the hook payload. Absent: the hook skips with a
  visible once-per-session notice. [Install jq](https://jqlang.org/download/).
- **ShellCheck** on `PATH` for the lint pass. Absent: the lint pass skips with
  a visible once-per-session notice.
- **shfmt** on `PATH` for the format pass (and an `.editorconfig` in your repo
  to opt in). Absent while the repo opts in: the format pass skips with a
  visible once-per-session notice. Without the `.editorconfig` opt-in the
  format pass stays quiet — the repo chose not to format.

Each pass is independent: when a tool is absent its pass is skipped (visibly)
and the other still runs.

The hook itself runs on Bash 3.2+. Telemetry timing uses `EPOCHREALTIME`
(Bash 5.0+); on older bash the telemetry envelope is skipped while linting and
formatting still run.

## Install

```shell
/plugin marketplace add melodic-software/claude-code-plugins
/plugin install bash-format@melodic-software
```

Then verify prerequisites with `/bash-format:setup check`.

## Configuration

The linting and formatting rules come from the `.shellcheckrc` and
`.editorconfig` already in your repository, which the plugin reads automatically.
To change the rules, edit those files.

One `userConfig` option tunes the hook itself:

| Option | Default | Effect |
|--------|---------|--------|
| `bash_format_enabled` | `true` | Toggle for the bash-format hook; set `false` for a clean no-op. |

Set it interactively with `/plugin configure bash-format`, or headless on the
install command:

```shell
claude plugin install bash-format@melodic-software --config bash_format_enabled=false
```

These options are user-scoped (stored in your user settings, not the project's).
To turn the hook off for a single repository, disable the whole plugin in that
project's `enabledPlugins` instead.

## License

MIT (SPDX-License-Identifier: MIT).
