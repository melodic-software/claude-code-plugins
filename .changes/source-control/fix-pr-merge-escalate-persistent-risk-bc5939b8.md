---
bump: patch
---

### Fixed

- The unattended merge gate escalates a MED or HIGH risk refusal that persists across two runs at the same head: when the identity's `<!-- babysit-merge-risk -->` reasons comment read before the run already names the current head, the run keeps or rewrites that comment and then adds the tracker's human-gated role label through the escalation contract, once. A new head or a LOW score adds nothing, report-only writes nothing, and no run removes the label. The writes report gains `riskEscalation`.
