---
bump: patch
---

### Changed

- A pr-merge `risk:MED` or `risk:HIGH` refusal whose reasons comment has stood unchanged at the head for `merge.risk-escalation-minutes` (new setting, 60) now gets its comment rewritten once to say the refusal persisted and needs a person, then the human-gated role label (the rewrite dates the comment beside the label, so the head-moved clear pairs them), while `merge.report-only` is false, so the pull request leaves the lane WIP count. A LOW score at that head first marks the comment cleared, so the time restarts with the next refusal. The README no longer says only a human removes that label: the `head-moved` clear does once the head moves. The README records the owner's finding-closure decision for #8450 and that the gate does not apply it yet (#8478).
