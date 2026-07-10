# Melodic Software — Claude Code plugins

A public [Claude Code](https://code.claude.com/docs) plugin marketplace of reusable, repo-agnostic
skills, hooks, and agents. Each plugin is designed to work in any repository and to be customized by
consumers without editing the plugin itself.

> Status: initialized. Plugins are migrated in one at a time; the catalog below grows as each is
> vetted and validated. See [`docs/MIGRATION-PLAYBOOK.md`](docs/MIGRATION-PLAYBOOK.md).

## Use this marketplace

```shell
/plugin marketplace add melodic-software/claude-code-plugins
/plugin install <plugin-name>@melodic-software
```

Browse and manage with `/plugin`. To refresh after updates: `/plugin marketplace update melodic-software`.

## Catalog

| Plugin | Type | What it does |
|---|---|---|
| [`markdown-formatter`](plugins/markdown-formatter) | Hook | Auto-formats and lints Markdown on edit via markdownlint-cli2, using the consuming repo's own markdownlint config. |
| [`bash-lint`](plugins/bash-lint) | Hook | Lints shell scripts on edit via ShellCheck, and formats via shfmt when the repo opts in with an `.editorconfig`, using the consuming repo's own config. |
| [`biome-format`](plugins/biome-format) | Hook | Formats and lints JS/TS/JSX/JSON on edit via Biome, only when the repo opts in with a `biome.json`, using the consuming repo's own Biome config. |
| [`ruff-format`](plugins/ruff-format) | Hook | Formats and lints Python on edit via Ruff, only when the repo opts in with a Ruff config (`ruff.toml`, `.ruff.toml`, or `pyproject.toml` `[tool.ruff]`), using the consuming repo's own Ruff config. |
| [`eol-normalizer`](plugins/eol-normalizer) | Hook | Normalizes a file's working-tree line endings on edit to its `.gitattributes` `eol=` value via `git check-attr` — symmetric CRLF↔LF, binary-safe, using the consuming repo's own attributes. |
| [`desktop-notification`](plugins/desktop-notification) | Hook | Alerts you when Claude Code needs input via an audible bell, an OSC 9 terminal notification, and an OS-native toast (macOS/Linux) on permission and idle prompts. |
| [`powershell-format`](plugins/powershell-format) | Hook | Formats and lints PowerShell on edit via PSScriptAnalyzer, only when the repo opts in with a `PSScriptAnalyzerSettings.psd1`, using the consuming repo's own analyzer settings. |
| [`actionlint`](plugins/actionlint) | Hook | Lints GitHub Actions workflow files (`.github/workflows/*.yml`/`.yaml`) on edit via the `actionlint` already on your `PATH` — advisory findings, never blocking. |
| [`book-distill`](plugins/book-distill) | Skill | Distills a technical book (PDF or EPUB) into concept-organized, author-attributed skill reference files through a structured multi-session read-write pipeline, updating the target skill's routing table. |

Install one: `/plugin install <plugin-name>@melodic-software`.

## What's here

- `.claude-plugin/marketplace.json` — the marketplace catalog.
- `plugins/` — one directory per plugin.
- `docs/MIGRATION-PLAYBOOK.md` — design charter, extensibility model, and the per-plugin migration gate.
- `CLAUDE.md` — operating rules for AI agents working in this repo (fresh-docs mandate + canonical links).

## Official documentation

This repo tracks policy and wiring only; authoritative behavior lives in the official docs, which must
be read fresh rather than recalled. Start at the
[Claude Code plugins guide](https://code.claude.com/docs/en/plugins).

## License

[MIT](LICENSE).
