---
bump: major
---

### Changed

- The git-hook entry and the opt-in end-of-turn check run the typos adapter only where the repository's own typos config governs the file (`typos.toml`, `_typos.toml`, `.typos.toml`, a `pyproject.toml` `[tool.typos]` section or a `Cargo.toml` `[workspace.metadata.typos]` or `[package.metadata.typos]` section, in the file's directory or above it), through the shared format and lint runner. With no such config nothing runs. The hooks never run a command from the repository's spelling record (`.claude/ecosystems/spelling.yaml`); `/toolchain:lint` and `/toolchain:check` run its `lint-cmd` on request, and `setup check` says when a record exists. File names reach typos as arguments.
- typos exiting non-zero with no `<path>:<line>` finding fails the commit closed and shows its output.
- `setup check` reports the lint concern from the entry's `--resolve` row (with paths, one row per file, naming the config that governs it), and grades a missing typos FAIL only where that row resolves the adapter. `setup apply` drafts a `lint-cmd` for `/toolchain:setup apply spelling` when the repository uses a spell-checker the plugin ships no adapter for, and never writes the record.
- The SessionStart probe reports a missing `typos` only where a typos config sits in the project directory or above it.

### Removed

- The `typos-check` git-hook entry is retired for `lint`, which reports typos on added lines and rewrites nothing. Installed copies, lefthook jobs and the `checks.spelling.typos-check.declined` key change; `setup check` reports an installed `typos-check` copy as superseded, `apply install-git-hooks` retires it, and a decline of `typos-check` carries to `lint`.
- A repository with no typos config is no longer spell-checked with the bundled config alone; add a typos config to opt in.
