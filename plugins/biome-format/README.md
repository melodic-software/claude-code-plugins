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

- **Opt-in on `biome.json`.** Biome runs **only when a Biome configuration
  governs the edited file** — `biome.json`, `biome.jsonc`, `.biome.json`, or
  `.biome.jsonc`, found by walking up from the file to the repository root. A
  repo without a Biome config is left untouched rather than rewritten to Biome's
  built-in defaults, so the plugin never imposes a style you did not choose.
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

- **Biome** available to the repo — installed in the repo's `node_modules`
  (the hook runs `node_modules/.bin/biome`) or on `PATH`. Biome is never
  downloaded on the fly; if it is not present, the hook is a silent no-op.
- A **`biome.json`** (or `.jsonc` / dotted variant) in the repo — the opt-in.

The hook itself runs on Bash 3.2+. Telemetry timing uses `EPOCHREALTIME`
(Bash 5.0+); on older bash the telemetry envelope is skipped while formatting and
linting still run.

## Install

```shell
/plugin marketplace add melodic-software/claude-code-plugins
/plugin install biome-format@melodic-software
```

## Configuration

This plugin has no `userConfig` — its only "configuration" is the `biome.json`
already in your repository, which it reads automatically. To change the rules,
edit that file.

### Disable without uninstalling

Set the kill switch in your settings `env` block:

```json
{ "env": { "HOOK_BIOME_FORMAT_ENABLED": "false" } }
```

## License

[MIT](../../LICENSE).
