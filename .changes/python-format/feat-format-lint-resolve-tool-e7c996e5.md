---
bump: major
---

### Changed

- Formatting and linting are separate concerns, each resolved per repository: the repository's python record (`.claude/ecosystems/python.yaml`: `fix-cmd` formats, `lint-cmd` lints), else the Ruff adapter where a Ruff config governs the file, else nothing. A record can name any tool. A record committed to the repository runs only when it, and every repository file its command names, match the default branch, or after `/python-format:setup apply approve-record`; otherwise it runs nothing, not even the adapter. A command must hold `<files>` to run from a hook, and file names reach it as arguments, never as shell text.
- `setup check` reports, per concern, the resolved tool, its source and its approval state, read from the resolver. `setup apply` drafts `fix-cmd` and `lint-cmd` for `/toolchain:setup apply python` and never writes the record. The SessionStart probe reports a missing `ruff` only where a Ruff config is present.

### Removed

- No lint autofix runs any more, in session or at commit: the batch hook and the `format` entry only format, and the Ruff adapter sorts imports only where the repository's lint config selects the import rules. A repository that relied on Ruff's safe fixes (an unused import removed, for example) applies them itself.
- The single `ruff-check` git-hook entry is retired for `format` (rewrites and re-stages) and `lint` (reports findings on added lines and fails closed when the linter exits non-zero without a `<path>:<line>` finding). Installed copies, lefthook jobs and the `checks.python-format.ruff-check.declined` key change; `setup check` reports an installed `ruff-check` copy as superseded, `apply install-git-hooks` retires it, and a decline of `ruff-check` carries to both new entries.
- The SessionStart probe no longer reports a missing `ruff` where no Ruff config is present.
