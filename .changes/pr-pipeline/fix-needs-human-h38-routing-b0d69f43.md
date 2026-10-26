---
bump: minor
---

### Changed

- `enable-auto-merge.mjs` adds the human-gated label only for a cause a person must clear (owner rule 2026-10-26): untrusted provenance or an untrusted spec (the gate's `needsHuman`), a risk hold the gate marks `reviewsPerson`, a hold path, a cost hold, or the lane's own hold line. The repeated-FAIL round cap, an old pull request, a changed spec, an issue's labels that did not read, and changed files that could not all be read get the comment alone, and the next scheduled runs judge them again.
- A refusal the lanes clear that has stood unchanged at the head for `merge.risk-escalation-minutes` shows as a failing `pr-merge/unarmed` commit status on the head, and an arm posts a passing one. The new `unarmed-status` job in `pr-merge.yml` posts them with the job's own token (`contents: read`, `statuses: write`, no lane token); the status is informational, not `ci-status`.
