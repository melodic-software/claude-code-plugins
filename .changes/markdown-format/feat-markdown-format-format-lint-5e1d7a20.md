---
bump: major
---

### Changed

- Formatting and linting are separate concerns, each with its own git-hook entry and its own row in `setup check`. The hooks run only the markdownlint-cli2 adapter, where a markdownlint config governs the file (a config that can run repository code only once the user approved its state, as before), and otherwise nothing. They never run a command from the repository's markdown record (`.claude/ecosystems/markdown.yaml`); `/toolchain:lint` and `/toolchain:check` run it on request, and `setup check` says when a record exists.
- File names reach markdownlint-cli2 as literal paths and as arguments, never as globs or shell text: a name holding `[`, or starting with `#` or `-`, is checked as itself.
- The lint entry checks a copy of the content under check (the staged content at commit, the work tree's at turn end), so a config whose `fix` property is true no longer rewrites files during a check, and a partly staged file is linted as the commit holds it instead of being refused.
- A lint run that exits non-zero with no `<path>:<line>` finding now fails closed and shows the tool's output; before, it passed.
- `setup check` reports, per concern, the adapter, its tool and whether it is found, read from the entries' `--resolve` rows (with paths, one row per file, naming the config that governs it or the trust verdict that holds it back). `setup apply` drafts `fix-cmd` and `lint-cmd` for `/toolchain:setup apply markdown` when the repository wants a tool the plugin ships no adapter for, and never writes the record.
- The turn-end check drops only missing-tool lines from what it reports, so a finding printed beside one still comes through.

### Removed

- The single `markdown-check` git-hook entry is retired for `format` (rewrites with `--fix` and re-stages, and reports nothing) and `lint` (reports findings on added lines, rewrites nothing). Installed copies, lefthook jobs and the `checks.markdown-format.markdown-check.declined` key change; `setup check` reports an installed `markdown-check` copy as superseded, `apply install-git-hooks` retires it, and a decline of `markdown-check` carries to both new entries.
- The SessionStart probe no longer reports a missing `markdownlint-cli2` where no markdownlint config sits in the project directory or above it.
