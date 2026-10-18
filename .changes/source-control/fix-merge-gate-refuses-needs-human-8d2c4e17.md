---
bump: minor
---

### Changed

- The babysit merge gate holds a pull request labelled `needs-human` as it holds one labelled `do-not-merge`, in every tier: `evaluate` reports the label as a blocker, `entry_hold` dequeues a queued identity entry that gains it, and the pr-merge prefilter drops such a candidate before the gate. The hold labels live in one tuple, `MERGE_HOLD_LABELS`, read through `merge_hold_label`. The verifier escalation still adds `needs-human` once; later runs drop the pull request before the gate, so it is not escalated again, and the escalating run's reason still names the verifier refusal. An attended merge of a `needs-human` pull request now needs the label removed first.
