---
bump: minor
---

### Added

- pr-unblock's `sync-shared-copies` activity answers pr-merge's `shared-copy-sources-changed:` refusal on a lanes App pull request with no model and no person. `pr-unblock-dispatch.yml` sends one run per refused head; `sync-shared-copies-select` merges the pinned default branch tip and runs `.github/scripts/pr-unblock/sync-shared-copies.sh`, which runs the base's sync script, `scripts/lib` and registry only, refusing `shared-copy-tooling-changed` when the head changes any of them and `shared-copy-path-unregistered` when the run writes a path the base-tip `scripts/shared-copies.txt` lists as no copy; `apply-shared-copies` pushes one merge commit under patch-rules.json's `shared-copies` row, which admits only registered copies.
- `gate-source.mjs` reads pr-merge's `shared-copy-sources-changed:` escalation at the current head as a gate the `sync-shared-copies` activity alone works past, through `laneEscalationAllows`, so `lane-hold.mjs` and `gate-recheck.mjs` both accept it.
- escalation-routes.json routes the `shared-copy-*` reasons to `sync-shared-copies`.
