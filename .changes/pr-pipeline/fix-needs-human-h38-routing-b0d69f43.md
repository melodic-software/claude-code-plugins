---
bump: minor
---

### Changed

- `enable-auto-merge.mjs` adds the human-gated label only for a cause a person must clear (owner rule 2026-10-26): a refusal the gate marks `needsHuman` (an untrusted spec, the repeated-FAIL cap, a pull request too old to verify), the trust hold, a risk hold the gate marks `reviewsPerson`, a hold path, a cost hold, a listing past 300 files (a fourth page that is not empty; no later read completes it), or the lane's own hold line. A changed spec and a changed-file page that did not read get the comment alone, and the next scheduled runs judge them again. `merge-holds.pathHoldKind` reports a path hold's kind, so the routing reads no prose.
- A refusal the lanes clear that has stood at the head for `merge.risk-escalation-minutes`, timed from the first lane refusal noted there (the comment's `pr-merge-unarmed-since` line), shows as a failing `pr-merge/unarmed` commit status on the head; an arm, the refusal becoming a person's, or a member's veto or a person turning auto-merge off standing in for it posts a passing one over it; a run that read nothing new (no time left, unread hold paths, a verdict that did not read) leaves the status alone. The new `unarmed-status` job in `pr-merge.yml` posts them with the job's own token (`contents: read`, `statuses: write`, no lane token) and trusts only a status the GitHub Actions bot posted; the status is informational, not `ci-status`.
