---
bump: minor
---

### Changed

- Formatting and linting are separate concerns, each resolved per repository: the repository's python record (`.claude/ecosystems/python.yaml`: `fix-cmd` formats, `lint-cmd` lints), else the Ruff adapter where a Ruff config governs the file, else nothing. A record can name any tool. A record committed to the repository runs only when it, and every repository file its command names, match the default branch, or after `/python-format:setup apply approve-record`; otherwise it runs nothing, not even the adapter. A command must hold `<files>` to run from a hook, and file names reach it as arguments, never as shell text.
- The batch hook formats only. No lint autofix runs in session or at commit; the Ruff adapter sorts imports only where the repository's lint config selects the import rules, then formats.
- The single `ruff-check` git-hook entry becomes two: `format` rewrites and re-stages, `lint` reports findings on added lines and fails closed when the linter exits non-zero without a `<path>:<line>` finding. `setup check` reports an installed `ruff-check` copy as superseded and `apply install-git-hooks` retires it; a decline of `ruff-check` carries to both entries.
- `setup check` reports, per concern, the resolved tool, its source and its approval state, read from the resolver. `setup apply` drafts `fix-cmd` and `lint-cmd` for `/toolchain:setup apply python` and never writes the record. The SessionStart probe reports a missing `ruff` only where a Ruff config is present.
