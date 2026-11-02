---
bump: major
---

### Changed

- `/work-items:work-loop`'s intake sweep no longer applies `agent-ready` or a `work-class:` label by default. A delegable, decision-defaulted or multi-surface stub outcome now takes the human-gated role label (default `needs-human`) and a `kind=escalated` marker with a `Proposed work class:` line, so a label the lane applied under its own identity can no longer admit an item. To keep the old behavior, a launch prompt must explicitly opt the sweep into writing those labels; a general grant of triage mutations does not count.
