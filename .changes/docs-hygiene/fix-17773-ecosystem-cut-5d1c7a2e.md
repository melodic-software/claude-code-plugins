---
bump: major
---

### Changed

- **Breaking:** `/docs-hygiene:compress` no longer runs `markdownlint-cli2` from `PATH` or `node_modules/.bin`, and no longer stops when it is absent. It finds your repository's own markdown lint command through the plugin's new copy of the ecosystem resolution steps (`reference/ecosystem-resolution.md`) and runs it scoped to each edited file: it passes the file when the command lints only the paths it is given, otherwise compares against a run taken before the edit and counts only new failures that name the file. It runs only a command that reads: one that can write files (a `--fix` or `--write` flag, a fix or write option in the linter's config file, or a recorded `fix-cmd`) is never run, and the target reports `lint=unresolved`. It compares `git status --porcelain -uall` and the hashes of every tracked and untracked file before and after each lint run; if any file changed, the target included, it stops, reports `lint=unresolved` and names the changed files. A failure in another file no longer reverts a compression; a command it cannot scope marks the target `lint=unresolved`. When none resolves, it skips the lint step, marks each target `lint=unresolved` and ships after every other check. The summary field is now `lint=PASS|FAIL|unresolved`, not `markdownlint=PASS|FAIL`. To keep the lint gate, record the command in `docs/conventions/ecosystems/<ecosystem>.yaml` (`/toolchain:setup apply <ecosystem>`), state it in your instructions, or declare it as a manifest script ([#17773](https://github.com/melodic-software/claude-code-plugins/issues/17773)).
- **`compress`, `audit-derivability` and `rename-references` no longer name tools from one ecosystem.** The code-file extension examples, the named cross-vendor advisor plugin, the `package.json` / `pyproject.toml` / `Cargo.toml` manifest examples in the container-mode ladder and Form 14, and the Python / C# / JS rename examples are gone; the rules now state them in general terms ([#17773](https://github.com/melodic-software/claude-code-plugins/issues/17773)).

### Removed

- **`/docs-hygiene:setup` no longer checks `markdownlint-cli2`.** It validates the `compress_articles` setting only ([#17773](https://github.com/melodic-software/claude-code-plugins/issues/17773)).
