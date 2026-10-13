---
bump: minor
---

### Added

- `babysit-loop` ships `scripts/publish-promotion-evidence.mjs`, an operator-side publisher for the promotion-evidence events file (#4588). It reads GitHub only, through read-only `gh api` calls, and emits the `{cell, event, at}` contrary events the security-binding checker reads (`reverted-merge`, `gate-failure`, and `verification-divergence` for a missed-blocking finding a human confirmed) plus a C3 promotion-evidence report: each promotable cell's predicate terms with counts, window and pass or fail. Report mode, the default, writes nothing. `--out <dir>` writes `evidence.json` and an `evidence.meta.json` sidecar (`generated_at`, `through`, `sha256`, `prev_sha256`) by temp file and rename, and refuses a set that drops a previously published event. Where it runs and under which identity is not decided yet, and the resolver does not read the sidecar; merge authority is unchanged.
