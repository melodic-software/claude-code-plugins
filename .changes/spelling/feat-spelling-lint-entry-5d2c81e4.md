---
bump: major
---

### Changed

- The git-hook entry and the opt-in end-of-turn check run typos through the shared format and lint runner, as the plugin's typos adapter (`git-hooks/adapters.sh`). It runs with or without a repository typos config, as before. The hooks never run a command from the repository's spelling record (`.claude/ecosystems/spelling.yaml`); `/toolchain:lint` and `/toolchain:check` run its `lint-cmd` on request, and `setup check` says when a record exists. File names reach typos as arguments.
- typos exiting non-zero with no `<path>:<line>` finding fails the commit closed and shows its output.
- `setup check` reports the lint concern from the entry's `--resolve` row (with paths, one row per file, naming the typos config that governs it, or saying none does). `setup apply` drafts a `lint-cmd` for `/toolchain:setup apply spelling` when the repository uses a spell-checker the plugin ships no adapter for, and never writes the record.

### Removed

- The `typos-check` git-hook entry is retired for `lint`, which reports typos on added lines and rewrites nothing. Installed copies, lefthook jobs and the `checks.spelling.typos-check.declined` key change; `setup check` reports an installed `typos-check` copy as superseded, `apply install-git-hooks` retires it, and a decline of `typos-check` carries to `lint`.
