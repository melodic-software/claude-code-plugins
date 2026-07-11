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
| [`guardrails`](plugins/guardrails) | Hook | Bundles four independently-toggleable PreToolUse safety guards: secret-pattern detection, hardcoded machine-path check, git hook-bypass blocking (`--no-verify`, `core.hooksPath`, `LEFTHOOK=0`), and advisory CLI-flag verification. |
| [`bug-report`](plugins/bug-report) | Skill | Turns an informal defect description into a structured five-field bug report (title, repro, expected vs actual, severity, fix location). Read-only — it captures, never fixes or files on its own. |
| [`diagnose`](plugins/diagnose) | Skill | Debugs observed failures via a disciplined six-phase loop — build a fast deterministic reproduction signal, reproduce, rank falsifiable hypotheses, instrument, fix with a regression test, then clean up and post-mortem. |
| [`improve-architecture`](plugins/improve-architecture) | Skill | Scans an existing codebase for module-level architecture friction — shallow modules, seam leaks, locality gaps — using Ousterhout's deep-module lens, presents candidates as a self-contained HTML report, and interviews the selected candidate before handing off for planning. |
| [`mcp-tool-audit`](plugins/mcp-tool-audit) | Skill | Audits MCP server tool definitions against MCP-spec and Anthropic tool-design criteria, returning a per-tool PASS/WARN/FAIL scorecard. Language-agnostic (Python, TypeScript, .NET). |
| [`prototype`](plugins/prototype) | Skills | Builds throwaway code to answer a design question before committing to architecture. Ships two skills: `/prototype:logic` (an interactive terminal app over a portable state model) and `/prototype:ui` (radically different visual variants on one route). |
| [`book-distill`](plugins/book-distill) | Skill | Distills a technical book (PDF or EPUB) into concept-organized, author-attributed skill reference files through a structured multi-session read-write pipeline, updating the target skill's routing table. |
| [`context7`](plugins/context7) | Skill | Looks up current library documentation, API references, and code examples via Context7 — a two-step resolve-then-query workflow over the `ctx7` CLI or the consumer's Context7 MCP server, plus an upstream drift-check `update` action. |
| [`thariq-skills`](plugins/thariq-skills) | Skill | Ships Anthropic's internal skill-authoring playbook as an on-demand knowledge skill — 9 skill categories, 9 authoring tips (gotchas sections, progressive disclosure, description-as-trigger), and distribution guidance, with a vendored upstream baseline and drift-check update script. |
| [`boris`](plugins/boris) | Skill | Ships Boris Cherny's Claude Code workflow tips (howborisusesclaudecode.com) as an on-demand knowledge skill — 107 tips across 95 sections routed through topic reference files, with a vendored upstream baseline and drift-check update script. |
| [`docs-hygiene`](plugins/docs-hygiene) | Skills | Documentation-hygiene toolkit of five skills: `/docs-hygiene:compress` (flavor-trim markdown behind a semantic-diff safety net), `/docs-hygiene:declutter` (classify markdown noise, read-only), `/docs-hygiene:extract-ssot` (deduplicate repeated content into a single source of truth), `/docs-hygiene:encapsulation-audit` (detect citations into skill-private surfaces), and `/docs-hygiene:rename-references` (sweep stale references after renames). |
| [`fable-5-playbook`](plugins/fable-5-playbook) | Skill | Ships Claude Fable 5's operating doctrine as an on-demand knowledge skill — core standing instructions plus twelve trigger-routed chapters (calibration, reasoning moves, planning, debugging, orchestration, verification, recovery, trust boundaries, and more) and an Opus-adaptation chapter for non-Fable models. |
| [`firecrawl`](plugins/firecrawl) | Skill | Web scraping, search, crawling, URL discovery, browser interaction, and local file parsing through the `firecrawl-cli` binary — results written to disk and read back selectively to keep large pages out of context, plus a gated maintainer update flow tracking the upstream CLI and skill source. |

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
