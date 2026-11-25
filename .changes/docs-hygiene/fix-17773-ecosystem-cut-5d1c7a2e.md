---
bump: patch
---

### Changed

- **`/docs-hygiene:compress` no longer requires `markdownlint-cli2`.** It finds your repository's own markdown lint command through the plugin's new copy of the ecosystem resolution steps (`reference/ecosystem-resolution.md`) and runs it on each edited file. When none resolves, it skips the lint step, marks each target `lint=unresolved` and still runs every other check; it no longer stops at its entry point. The summary field is now `lint=PASS|FAIL|unresolved` ([#17773](https://github.com/melodic-software/claude-code-plugins/issues/17773)).
- **`/docs-hygiene:setup` no longer checks `markdownlint-cli2`.** It validates the `compress_articles` setting only ([#17773](https://github.com/melodic-software/claude-code-plugins/issues/17773)).
- **`compress`, `audit-derivability` and `rename-references` no longer name tools from one ecosystem.** The code-file extension examples, the named cross-vendor advisor plugin, the `package.json` / `pyproject.toml` / `Cargo.toml` manifest examples in the container-mode ladder and Form 14, and the Python / C# / JS rename examples are gone; the rules now state them in general terms ([#17773](https://github.com/melodic-software/claude-code-plugins/issues/17773)).
