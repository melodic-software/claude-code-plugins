# markdown-formatter

A Claude Code plugin that auto-formats and lints Markdown the moment you edit it.
On every `Write` or `Edit` of a `.md` or `.mdc` file it runs
[`markdownlint-cli2 --fix`](https://github.com/DavidAnson/markdownlint-cli2) from
the file's repository root, applying every auto-fixable rule and surfacing the
residual (unfixable) findings back to Claude as advisory context.

It uses **your repository's own markdownlint configuration** — it ships none and
imposes no rules of its own.

## Behavior

- **Auto-fix on edit.** Fixable violations (final newline, list-marker style,
  trailing spaces, …) are corrected in place.
- **Advisory, never blocking.** The hook always exits `0`. Unfixable findings are
  reported via `additionalContext`; they never reject the edit. Make a commit
  hook or CI your hard gate.
- **Config from the consumer.** `markdownlint-cli2` discovers config
  (`.markdownlint-cli2.jsonc`, `.markdownlint.json`, …) by walking up from the
  repository root. The hook `cd`s to that root before linting so the right
  cascade applies regardless of the session's working directory.

## Requirements

`markdownlint-cli2` must be resolvable — installed globally, or reachable via
`npx` (the hook falls back to `npx markdownlint-cli2`). When neither is present
the hook is a silent no-op.

The hook itself runs on Bash 3.2+. Telemetry timing uses `EPOCHREALTIME`
(Bash 5.0+); on older bash the telemetry envelope is skipped while formatting
still runs.

## Install

```shell
/plugin marketplace add melodic-software/claude-code-plugins
/plugin install markdown-formatter@melodic-software
```

## Configuration

This plugin has no `userConfig` — its only "configuration" is the markdownlint
config already in your repository, which it reads automatically. To change the
rules, edit your repo's markdownlint config.

### Disable without uninstalling

Set the kill switch in your settings `env` block:

```json
{ "env": { "HOOK_MARKDOWN_FORMAT_ENABLED": "false" } }
```

## License

[MIT](../../LICENSE).
