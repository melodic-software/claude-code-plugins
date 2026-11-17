---
bump: major
---

### Changed

- Formatting and linting are separate concerns, each with its own git-hook entry and its own row in `setup check`. The hooks run only the shipped adapters, through the shared runner (`lib/git-hooks/resolve-tool.sh`): shfmt where an `.editorconfig` section names shell files, as before, and ShellCheck on every staged shell file, as before (with the repository's `.shellcheckrc` when it has one). They never run a command from the repository's bash record (`.claude/ecosystems/bash.yaml`); `/toolchain:lint` and `/toolchain:check` run it on request, and `setup check` says when a record exists.
- `setup check` reports, per concern, the adapter, its tool and whether it is found, read from the entries' `--resolve` rows (with paths, one row per file, naming the config that governs it). `setup apply` drafts `fix-cmd` and `lint-cmd` for `/toolchain:setup apply bash` when the repository wants a tool the plugin ships no adapter for, and never writes the record.
- The `lint` entry fails closed when ShellCheck exits 1 with no `<path>:<line>` finding, showing its output.
- The opt-in end-of-turn check runs the `lint` entry and drops only missing-tool lines from what it hands back, so a finding printed beside one still reaches Claude.

### Fixed

- A staged shell script whose name starts with `-` is formatted as a path instead of being read by shfmt as a flag.

### Removed

- The single `shell-check` git-hook entry is retired for `format` (rewrites and re-stages) and `lint` (reports findings on added lines). Installed copies, lefthook jobs and the `checks.bash-format.shell-check.declined` key change; `setup check` reports an installed `shell-check` copy as superseded, `apply install-git-hooks` retires it, and a decline of `shell-check` carries to both new entries.
- The SessionStart probe no longer reports a missing `shfmt` where no `.editorconfig` shell section is present, since nothing would run it there.
