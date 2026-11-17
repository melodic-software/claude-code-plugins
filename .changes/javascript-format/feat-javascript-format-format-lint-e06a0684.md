---
bump: major
---

### Changed

- Formatting and linting are separate concerns, each with its own git-hook entry and its own row in `setup check`. The hooks run only the Biome adapter, where a `biome.json` or `biome.jsonc` governs the file, and otherwise nothing. They never run a command from the repository's typescript, javascript or json record (`.claude/ecosystems/<id>.yaml`); `/toolchain:lint` and `/toolchain:check` run it on request, and `setup check` says when a record exists. File names reach Biome as arguments, never as shell text.
- Format runs `biome check --write --linter-enabled=false`: the formatter and the assist actions the repository's config enables, import sorting by default. Lint runs `biome lint` and reports only.
- `setup check` reports, per concern, the adapter, its tool and whether it is found, read from the entries' `--resolve` rows (with paths, one row per file, naming the config that governs it and the binary). `setup apply` drafts `fix-cmd` and `lint-cmd` for `/toolchain:setup apply <id>` when the repository wants a tool the plugin ships no adapter for, and never writes the record. `apply install-biome` follows principles that resolve the package manager from the repository at run time instead of a list of managers.
- The opt-in end-of-turn check runs the `lint` entry and drops only missing-tool lines from what it hands back, so a finding printed beside one still reaches Claude.

### Removed

- No lint fix runs any more, in session or at commit: the batch hook and the `format` entry only format. A repository that relied on Biome's safe lint fixes (`let` to `const` under `useConst`, for example) applies them itself.
- The single `biome-check` git-hook entry is retired for `format` (rewrites and re-stages) and `lint` (reports findings on added lines and fails closed when Biome exits non-zero without a `<path>:<line>` finding, as it does on a config it cannot parse). Installed copies, lefthook jobs and the `checks.javascript-format.biome-check.declined` key change; `setup check` reports an installed `biome-check` copy as superseded, `apply install-git-hooks` retires it, and a decline of `biome-check` carries to both new entries.
- The SessionStart probe no longer reports a missing `biome` where no `biome.json` or `biome.jsonc` sits at or above the project directory.
