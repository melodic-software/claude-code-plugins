---
bump: minor
---

### Changed

- An unattended merge (`babysit_merge.py --unattended`, which the pr-merge lane runs) holds a pull request labelled `needs-human` as it holds one labelled `do-not-merge`: `evaluate` reports the label as a blocker, `entry_hold` dequeues a queued identity entry that gains it, and the pr-merge prefilter drops such a candidate before the gate. An attended merge still merges a `needs-human` pull request, since that label asks for the person merging it; `do-not-merge` still holds every tier. The labels live in `MERGE_HOLD_LABELS` (every tier) and `UNATTENDED_HOLD_LABELS` (adds `needs-human`), read through `merge_hold_label(labels, unattended=...)`. The verifier escalation still adds `needs-human` once; later pr-merge runs drop the pull request before the gate, so it is not escalated again, and the escalating run's reason still names the verifier refusal.
