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

- **Ruff** available to the repo — installed in the repo's `.venv` (the hook
  resolves `.venv/bin/ruff`, or `.venv/Scripts/ruff.exe` on Windows, walking up
  from the edited file) or on `PATH`. Ruff is never downloaded on the fly; if
  it is not present, the hook is a silent no-op. **Ruff 0.12+ is recommended**
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

## Configuration

This plugin has no `userConfig` — its only "configuration" is the Ruff config
already in your repository, which it reads automatically. To change the rules,
edit that file.

### Disable without uninstalling

Set the kill switch in your settings `env` block:

```json
{ "env": { "HOOK_RUFF_FORMAT_ENABLED": "false" } }
```

## License

MIT (SPDX-License-Identifier: MIT). See the `LICENSE` file at the root of the
melodic-software/claude-code-plugins repository.
