---
bump: minor
---

### Changed

- An unattended merge (`babysit_merge.py --unattended`, which the pr-merge lane runs) holds a pull request carrying the tracker's human-gated role label (`needs-human` unless `.work-item-tracker.json` maps `human-gated` to another) as it holds one labelled `do-not-merge`: `evaluate` reports the label as a blocker, `entry_hold` dequeues a queued identity entry that gains it, and the pr-merge prefilter drops such a candidate before the gate (`--human-gated`, which `pr-merge.yml` resolves from the base `.work-item-tracker.json`). The gate resolves the label through the same `babysit_postmerge._role_label` read the verifier escalation uses (`human_gated_label`, shared across a run's gate processes), so the label the escalation adds is the one every hold reads. An attended merge (no `--unattended`) still merges such a pull request, since that label asks for the person merging it; `do-not-merge` still holds every tier. A later escalation of an already-labelled pull request adds no second label or comment.
