# typos-format

A Claude Code plugin that auto-fixes source-code spelling mistakes the moment you edit
a file. On every `Write` or `Edit` it runs [`typos -w`](https://github.com/crate-ci/typos)
against the edited file, applying every unambiguous correction and surfacing the residual
(ambiguous) findings back to Claude as advisory context.

It ships no rules of its own — `typos` carries its own built-in spelling dictionary and
runs with zero configuration. It uses **your repository's own optional `_typos.toml`**
(or `typos.toml`, `.typos.toml`, a `[tool.typos]` section in `pyproject.toml`, or a
`[workspace.metadata.typos]`/`[package.metadata.typos]` section in `Cargo.toml`) to widen
its allowlist — for project-specific names, acronyms, or intentionally-kept misspellings —
and to exclude files, exactly as `typos` itself would if you ran it by hand.

## Behavior

- **Auto-fix on edit.** Every typo `typos` can correct unambiguously is applied in place.
- **Advisory, never blocking.** The hook always exits `0`. A residual finding — a typo with
  more than one plausible correction, which `typos` deliberately declines to apply
  unassisted — is reported via `additionalContext`; it never rejects the edit. Make a
  commit hook or CI your hard gate.
- **No file-type filter.** `typos` is a cross-language spell checker, not a
  single-ecosystem formatter, so this hook runs on every edited file and lets `typos`'
  own binary-content detection and your `_typos.toml` `[files]` excludes decide what
  actually gets checked.
- **Config and excludes from the consumer.** `typos` discovers its config by walking up
  from the **edited file itself** — not from this hook's own working directory — so
  discovery is correct regardless of where a session's shell happens to be. The hook
  passes `--force-exclude` so a `[files]` `extend-exclude` entry in your config is honored
  even for a file edited directly (by default `typos` only applies that exclude list
  during its own directory walk, not to an explicitly-named path).

## Requirements

The hook requires the following tools:

- Bash 3.2 or later. On native Windows, install
  [Git for Windows](https://code.claude.com/docs/en/setup#set-up-on-windows) so
  Claude Code can run this Bash hook; WSL is also supported.
- [`jq`](https://jqlang.org/) to parse hook input and emit structured context.
- [`typos`](https://github.com/crate-ci/typos#install), installed explicitly on `PATH`
  (a downloaded release binary, or via Cargo, Homebrew, Conda, or Pacman).

Missing prerequisites do not block an edit. Following Claude Code's
[PostToolUse contract](https://code.claude.com/docs/en/hooks#posttooluse-decision-control),
the hook exits `0` and reports a once-per-session notice to both Claude
(`additionalContext`) and you (`systemMessage`). It never installs `typos`, falls back to
a package runner, or performs a network request during a hook run.

Telemetry timing uses `EPOCHREALTIME` (Bash 5.0+); on older Bash the telemetry envelope is
skipped while the fix still runs.

## Install

```shell
/plugin marketplace add melodic-software/claude-code-plugins
/plugin install typos-format@melodic-software
```

Then verify the runtime prerequisites with `/typos-format:setup check`;
`/typos-format:setup apply` re-runs the check and points at remediation for anything it
reports.

## Configuration

Spelling corrections themselves are never configured here — the plugin's only rule source
is `typos`' own built-in dictionary plus whatever your repository's `_typos.toml` extends.
To silence a false positive (a name, acronym, or intentional spelling) or exclude a path,
edit your repo's `_typos.toml` — see the
[false positives](https://github.com/crate-ci/typos#false-positives) section of the typos
README and its [configuration reference](https://github.com/crate-ci/typos/blob/master/docs/reference.md).

One `userConfig` option tunes the hook itself:

| Option | Type | Default | Effect |
|--------|------|---------|--------|
| `typos_format_enabled` | boolean | `true` | Toggle the typos-format hook; set `false` for a clean no-op. |

Set it interactively with `/plugin configure typos-format`, or headless on the install
command:

```shell
claude plugin install typos-format@melodic-software --config typos_format_enabled=false
```

This option is user-scoped (stored in your user settings, not the project's). To disable
spell-checking for a single repository, disable the whole plugin in that project's
`enabledPlugins` instead.

## License

MIT (SPDX-License-Identifier: MIT).
