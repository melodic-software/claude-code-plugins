---
bump: patch
---

### Fixed

- The unattended merge gate escalates a MED or HIGH risk refusal that persists at one head: when the identity's `<!-- babysit-merge-risk -->` reasons comment read before the run already says the same score, reasons and head, and has stood unchanged for `merge.risk-escalation-minutes` (default 60; 0 is no minimum), the run rewrites that comment once to end with a line saying the refusal persisted and needs a person, then adds the tracker's human-gated role label through the escalation contract. The rewrite dates the comment beside the label, so the pr-pipeline head-moved clear can pair them and take the label off once the head moves. The minimum lets a review still running at the head, which scores MED, finish first. Changed reasons rewrite the comment and restart the time; a new head or a LOW score adds no label, report-only writes nothing, and no merge-gate run removes the label. The writes report gains `riskEscalation`.
