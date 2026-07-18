# markdown-format

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
  (`.markdownlint-cli2.jsonc`, `.markdownlint.json`, …) per edited file, from
  the file's directory up through its parents — so a nested config governs its
  subtree. The hook `cd`s to the repository root before linting so that
  discovery caps at the root regardless of the session's working directory.

## Requirements

The hook requires the following tools:

- Bash 3.2 or later. On native Windows, install
  [Git for Windows](https://code.claude.com/docs/en/setup#set-up-on-windows) so
  Claude Code can run this Bash hook; WSL is also supported.
- [`jq`](https://jqlang.org/) to parse hook input and emit structured context.
- [`markdownlint-cli2`](https://github.com/DavidAnson/markdownlint-cli2),
  installed explicitly either on `PATH` or as a pinned dependency in the consuming
  repository. For the latter, the hook uses the extensionless
  `node_modules/.bin/markdownlint-cli2` shim that npm supplies for POSIX shells and Git
  Bash. It resolves symlinks first and rejects a shim whose physical target escapes the
  repository's `node_modules` tree.

Missing prerequisites do not block an edit. Following Claude Code's
[PostToolUse contract](https://code.claude.com/docs/en/hooks#posttooluse-decision-control),
the hook exits `0` and reports a once-per-session notice to both Claude
(`additionalContext`) and you (`systemMessage`). It never falls back to `npx`,
installs a package, or performs a network request during a hook run.

Telemetry timing uses `EPOCHREALTIME` (Bash 5.0+); on older Bash the telemetry
envelope is skipped while formatting still runs.

### Configuration trust boundary

`markdownlint-cli2` supports executable `.cjs`/`.mjs` configuration and can
load custom rules, Markdown-it plugins, and output formatters. Because the hook
runs the consuming repository's configuration, enable it only for repositories
whose configuration and installed dependencies you trust. Prefer declarative
JSONC or YAML when executable configuration is unnecessary. Before running a
risky configuration, the hook emits a non-blocking trust advisory once for each
repository and configuration-content state; changing that configuration causes
the advisory to appear again.

## Install

```shell
/plugin marketplace add melodic-software/claude-code-plugins
/plugin install markdown-format@melodic-software
```

Then verify the runtime prerequisites with `/markdown-format:setup check`;
`/markdown-format:setup apply` resolves anything the check reports with
guidance, and `/markdown-format:setup apply install-lint` additionally
authorizes installing `markdownlint-cli2` as a dev dependency using the
repository's own package manager.

## Configuration

The rules themselves are never configured here — the plugin's only rule source is
the markdownlint config already in your repository, which it reads automatically.
To change the rules, edit your repo's markdownlint config.

One `userConfig` option tunes the hook itself:

| Option | Type | Default | Effect |
|--------|------|---------|--------|
| `markdown_format_enabled` | boolean | `true` | Toggle the markdown-format hook; set `false` for a clean no-op. |

Set it interactively with `/plugin configure markdown-format`, or headless on
the install command:

```shell
claude plugin install markdown-format@melodic-software --config markdown_format_enabled=false
```

These options are user-scoped (stored in your user settings, not the project's).
To disable formatting for a single repository, disable the whole plugin in that
project's `enabledPlugins` instead.

## License

MIT (SPDX-License-Identifier: MIT). See the `LICENSE` file at the root of the
melodic-software/claude-code-plugins repository.
