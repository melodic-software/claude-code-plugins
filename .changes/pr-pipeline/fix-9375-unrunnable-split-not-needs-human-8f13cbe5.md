---
bump: patch
---

### Fixed

- An issue held before admission (an escalated or flagged intake verdict, or a hold label) whose done-when asks for what an unattended lane run cannot do now gets the admission comment that names those items and recommends the split, which a `needs_human` escalation used to drop. The intake rubric no longer sends such items through the `intent` flag: the model triages the lane-checkable items with their work class and leaves the hold to admission.
