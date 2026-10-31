---
bump: minor
---

### Added

- `.github/scripts/pr-unblock/sync-shared-copies.sh` regenerates a pull request's shared-library copies on a clean merge of the pinned base, with the base's sync script, `scripts/lib` and registry only. It refuses `shared-copy-tooling-changed` when the head changes any of them, and `shared-copy-path-unregistered` when the run writes a path the base-tip `scripts/shared-copies.txt` lists as no copy.
- `gate-source.mjs` reads pr-merge's `shared-copy-sources-changed:` escalation at the current head as a gate the `sync-shared-copies` activity alone works past, through `laneEscalationAllows`, so `lane-hold.mjs` and `gate-recheck.mjs` both accept it. The workflow jobs that run the activity are not wired yet.
