---
bump: patch
---

### Changed

- `verify:fail` joins the verifier refusals that need a human: while `merge.report-only` is false the pr-merge lane escalates it with the `<!-- babysit-merge-verify-escalation -->` comment, which for `verify:fail` quotes the head `fail` verdict's `summary` as data, and the human-gated role label, so a refused pull request leaves the lane WIP count.
