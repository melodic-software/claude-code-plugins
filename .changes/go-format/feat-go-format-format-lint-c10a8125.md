---
bump: major
---

### Changed

- The batch hook and the git pre-commit entry run the goimports adapter through the shared resolver (`lib/git-hooks/resolve-tool.sh`), still with no consumer-config gate. They never run a command from the repository's go record (`.claude/ecosystems/go.yaml`); `/toolchain:lint` and `/toolchain:check` run it on request, and `setup check` says when a record exists. File names reach goimports as arguments, never as shell text. `go list -m` runs once per directory instead of once per file.
- `setup check` reports what the format concern resolves to, read from the entry's `--resolve` rows (with paths, one row per file), and reports Go linting as INFO: the plugin ships no lint adapter, so the hooks run nothing for it. `setup apply` drafts a `lint-cmd` for `/toolchain:setup apply go` when the repository lints Go, and never writes the record.
- The opt-in end-of-turn check drops only missing-tool lines from what it hands back, so a parse error printed beside one still reaches Claude.

### Removed

- goimports runs with `-format-only`, in session and at commit: it formats and groups and orders imports, and no longer adds a missing import or removes an unused one, which are lint fixes. A repository that relied on that applies it itself.
- The `goimports-format` git-hook entry is renamed `format`. Installed copies, lefthook jobs and the `checks.go-format.goimports-format.declined` key change; `setup check` reports an installed `goimports-format` copy as superseded, `apply install-git-hooks` retires it, and a decline of `goimports-format` carries to `format`.
