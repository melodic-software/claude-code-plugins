---
bump: major
---

### Changed

- Formatting and linting are separate concerns, each with its own git-hook entry and its own row in `setup check`. The hooks run only the Ruff adapter, where a Ruff config governs the file, and otherwise nothing. They never run a command from the repository's python record (`.claude/ecosystems/python.yaml`); `/toolchain:lint` and `/toolchain:check` run it on request, and `setup check` says when a record exists. File names reach Ruff as arguments, never as shell text.
- `setup check` reports, per concern, the adapter, its tool and whether it is found, read from the entries' `--resolve` rows (with paths, one row per file, naming the config that governs it). `setup apply` drafts `fix-cmd` and `lint-cmd` for `/toolchain:setup apply python` when the repository wants a tool the plugin ships no adapter for, and never writes the record.
- The opt-in end-of-turn check drops only missing-tool lines from what it hands back, so a finding printed beside one still reaches Claude.

### Removed

- No lint autofix runs any more, in session or at commit: the batch hook and the `format` entry only format, and the Ruff adapter sorts imports only where the repository's lint config selects the import rules. A repository that relied on Ruff's safe fixes (an unused import removed, for example) applies them itself.
- The single `ruff-check` git-hook entry is retired for `format` (rewrites and re-stages) and `lint` (reports findings on added lines and fails closed when the linter exits non-zero without a `<path>:<line>` finding). Installed copies, lefthook jobs and the `checks.python-format.ruff-check.declined` key change; `setup check` reports an installed `ruff-check` copy as superseded, `apply install-git-hooks` retires it, and a decline of `ruff-check` carries to both new entries.
- The SessionStart probe no longer reports a missing `ruff` where no Ruff config is present.
