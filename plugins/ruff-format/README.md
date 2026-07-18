# ruff-format

A Claude Code plugin that formats and lints Python the moment you edit it. On
every `Write` or `Edit` of a `.py` or `.pyi` file it runs
[Ruff](https://docs.astral.sh/ruff/)'s `check --fix` (safe fixes only) and
`format`, then surfaces any residual findings back to Claude as advisory
context.

It uses **your repository's own Ruff configuration**. It ships no rules of its
own and runs only when your repo has opted into Ruff.

## Behavior

- **Opt-in on a Ruff config.** Ruff runs **only when a `.ruff.toml`,
  `ruff.toml`, or `pyproject.toml` with a `[tool.ruff]` section governs the
  edited file**, found by walking up from the file to the repository root — the
  same discovery Ruff itself uses (a `pyproject.toml` without `[tool.ruff]` is
  ignored, exactly as Ruff ignores it). A repo without a Ruff config is left
  untouched rather than rewritten to Ruff's built-in defaults, so the plugin
  never imposes a style you did not choose.
- **Fix + format on edit.** `ruff check --fix` applies safe fixes (never
  `--unsafe-fixes`) and `ruff format` formats in place. Residual diagnostics
  are reported but not auto-applied.
- **Just-added imports are protected.** The hook passes `--unfixable F401`, so
  an unused import is *reported* but never auto-deleted — during iterative
  editing an import often lands one edit before the code that uses it. This
  extends your config's own `unfixable` list; it does not replace it.
- **Syntax errors are version-aware.** Ruff's parser checks syntax against your
  configured `target-version` (or the `requires-python` floor it infers), so
  code using syntax newer than your Python floor surfaces as a finding.
- **Respects your excludes.** The hook passes `--force-exclude`, so a path your
  config excludes (generated or vendored code) is left untouched even though
  the hook passes it explicitly, with no advisory noise.
- **Advisory, never blocking.** The hook always exits `0`. Findings are
  reported via `additionalContext`; they never reject the edit. Make a commit
  hook or CI your hard gate.
- **No repo side effects.** The hook passes `--no-cache`, so Ruff never writes
  a `.ruff_cache` directory into your repo on edits.

## Requirements

- **Bash** — the hook is a Bash script. On native Windows, install
  [Git for Windows](https://code.claude.com/docs/en/setup#set-up-on-windows) so
  Claude Code can run it under Git Bash.
- **jq** on `PATH` — parses the hook payload. Absent: the hook skips with a
  visible once-per-session notice. [Install jq](https://jqlang.org/download/).
- **Ruff** available to the repo — installed in the repo's `.venv` (the hook
  resolves `.venv/bin/ruff`, or `.venv/Scripts/ruff.exe` on Windows, walking up
  from the edited file) or on `PATH`. Ruff is never downloaded on the fly; if
  it is not present while a Ruff config governs the repo, the hook skips with a
  visible once-per-session notice. **Ruff 0.12+ is recommended**
  (tested against 0.15.20): earlier releases lack stabilized version-aware
  syntax errors, and on much older releases the flags the hook passes may be
  absent, in which case the run is reported as a tool break rather than a
  finding.
- A **Ruff config** (`.ruff.toml`, `ruff.toml`, or `pyproject.toml` with
  `[tool.ruff]`) in the repo — the opt-in.

The hook itself runs on Bash 3.2+. Telemetry timing uses `EPOCHREALTIME`
(Bash 5.0+); on older bash the telemetry envelope is skipped while formatting
and linting still run.

## Install

```shell
/plugin marketplace add melodic-software/claude-code-plugins
/plugin install ruff-format@melodic-software
```

Then verify prerequisites with `/ruff-format:setup check`.

## Configuration

The rules themselves are never configured here — they come from the Ruff config
already in your repository, which the plugin reads automatically. To change the
rules, edit that file.

One `userConfig` option tunes the hook itself:

| Option | Default | Effect |
|--------|---------|--------|
| `ruff_format_enabled` | `true` | Kill switch — set `false` for a clean no-op. |

Set it interactively with `/plugin configure ruff-format`, or headless on the
install command:

```shell
claude plugin install ruff-format@melodic-software --config ruff_format_enabled=false
```

These options are user-scoped (stored in your user settings, not the project's).
To turn the plugin off for a single repository, disable it in that project's
`enabledPlugins` instead.

## License

MIT (SPDX-License-Identifier: MIT). See the `LICENSE` file at the root of the
melodic-software/claude-code-plugins repository.
