---
bump: patch
---

### Changed

- A pr-merge `risk:MED` or `risk:HIGH` refusal whose reasons comment has stood unchanged at the head for `merge.risk-escalation-minutes` (new setting, 60) now gets the human-gated role label, while `merge.report-only` is false, so the pull request leaves the lane WIP count. The README records the owner's finding-closure decision for #8450 and that the gate does not apply it yet (#8478).
