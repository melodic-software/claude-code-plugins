---
bump: minor
---

### Changed

- The commit-subject and PR-title convention that `block-convention-violation` and the `commit-msg-convention` git-hook entry enforce now resolves from `docs/conventions/source-control.yaml` first, read with the shared YAML-subset parser, which ships beside the resolver and installs as a second asset of the entry. For one release, a key that file lacks is read from the legacy surfaces: the `convention_source` neutral file or the well-known folder-form `commit-convention.yml`, then `.claude/source-control.md`. The YAML counts only while git tracks it, and a tracked file that does not parse, carries a key with an empty value, declares a dialect other than `posix-ere`, or is a symlink turns enforcement off with a diagnostic instead of falling back.
- A `commit-msg-convention` copy installed before this release keeps its old resolver, which does not read `docs/conventions/source-control.yaml`. Once the legacy surfaces are removed, such a copy enforces nothing until it is refreshed. `verify` reads it as `stale`, and the session-start notice names the refresh: run `/guardrails:setup apply install-git-hooks` before the legacy surfaces go.
- A commit-msg rejection names the file that holds the pattern, from the resolver's new `--layer` option, instead of always naming `.claude/source-control.md`.

### Fixed

- A git-hook entry installed before its manifest listed an asset now reads `stale` rather than `modified` in `verify` and `plan`, so `copy` refreshes it and adds the asset without `--force`. Deleting an asset the install's stamp covers still reads `modified`.
