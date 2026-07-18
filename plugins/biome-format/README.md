# biome-format

A Claude Code plugin that formats and lints JavaScript, TypeScript, JSX, and
JSON the moment you edit them. On every `Write` or `Edit` of a `.ts`, `.tsx`,
`.js`, `.jsx`, `.mjs`, `.cjs`, `.mts`, `.cts`, `.json`, or `.jsonc` file it runs
[Biome](https://biomejs.dev/)'s `check --write` — applying safe fixes,
formatting, and import sorting — then surfaces any residual findings back to
Claude as advisory context.

It uses **your repository's own `biome.json`**. It ships no rules of its own and
runs only when your repo has opted into Biome.

## Behavior

- **Opt-in on `biome.json`.** Biome runs **only when a `biome.json` or
  `biome.jsonc` governs the edited file**, found by walking up from the file to
  the repository root. A repo without a Biome config is left untouched rather
  than rewritten to Biome's built-in defaults, so the plugin never imposes a
  style you did not choose. (The hidden `.biome.json` / `.biome.jsonc` names are
  intentionally not treated as the opt-in: Biome only loads them from 2.4
  onward, so honoring them here would risk reformatting with built-in defaults on
  an older Biome. Use a canonical `biome.json` / `biome.jsonc`.)
- **Format + lint on edit.** `biome check --write` applies safe fixes,
  formatting, and import sorting in place. Residual diagnostics — errors and,
  because the hook passes `--error-on-warnings`, warnings — are reported but not
  auto-applied (unsafe fixes are never forced).
- **Respects your ignores.** Biome honors your config's `files.includes` ignore
  rules even for the single edited file. A path your config excludes (for
  generated or vendored code) is left untouched, with no advisory noise.
- **Advisory, never blocking.** The hook always exits `0`. Findings are reported
  via `additionalContext`; they never reject the edit. Make a commit hook or CI
  your hard gate.
- **Config discovery from your repo.** The hook finds the governing `biome.json`
  by walking up from the edited file and runs Biome from that config's directory,
  so a single repo-root (or subtree) config governs files in subdirectories
  beneath it.

## Requirements

- **Bash** — the hook is a Bash script. On native Windows, install
  [Git for Windows](https://code.claude.com/docs/en/setup#set-up-on-windows) so
  Claude Code can run it under Git Bash.
- **jq** on `PATH` — parses the hook payload. Absent: the hook skips with a
  visible once-per-session notice. [Install jq](https://jqlang.org/download/).
- **Biome** available to the repo — installed in the repo's `node_modules`
  (the hook runs `node_modules/.bin/biome`) or on `PATH`. Biome is never
  downloaded on the fly; if it is not present while a Biome config governs the
  repo, the hook skips with a visible once-per-session notice.
  **Biome 2.x is recommended** (tested against 2.5.1): the hook invokes
  `check --write --error-on-warnings --reporter=github`, and on much older
  releases those flags may be absent, in which case the run is reported as a
  tool break rather than a finding.
- A **`biome.json`** or **`biome.jsonc`** in the repo — the opt-in.

The hook itself runs on Bash 3.2+. Telemetry timing uses `EPOCHREALTIME`
(Bash 5.0+); on older bash the telemetry envelope is skipped while formatting and
linting still run.

## Install

```shell
/plugin marketplace add melodic-software/claude-code-plugins
/plugin install biome-format@melodic-software
```

## Configuration

The formatting rules come from the `biome.json` already in your repository, which
the plugin reads automatically. To change the rules, edit that file.

One `userConfig` option tunes the hook itself:

| Option | Default | Effect |
|--------|---------|--------|
| `biome_format_enabled` | `true` | Toggle for the biome-format hook; set to `false` for a clean no-op |

Set it interactively with `/plugin configure biome-format`, or headless on the
install command:

```shell
claude plugin install biome-format@melodic-software --config biome_format_enabled=false
```

These options are user-scoped (stored in your user settings, not the
project's). To turn the hook off for a single repository, disable the whole
plugin in that project's `enabledPlugins` instead.

## License

MIT (SPDX-License-Identifier: MIT). See the `LICENSE` file at the root of the
melodic-software/claude-code-plugins repository.
