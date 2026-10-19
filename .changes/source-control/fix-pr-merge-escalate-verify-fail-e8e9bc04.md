---
bump: patch
---

### Fixed

- The pr-merge lane escalates a `verify:fail` refusal (a counted verifier `fail` at the head) like the other refusals that need a human, once `merge.report-only` is false: one `<!-- babysit-merge-verify-escalation -->` comment naming the refusal and the head, quoting as data up to 1500 characters of the newest head `fail` verdict's `summary` when its record can be read, then the tracker's human-gated role label. A rerun at the same head and refusal writes nothing. The verify report gains `headFail` (run id and artifact name).
