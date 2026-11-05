---
bump: patch
---

### Fixed

- break equal-priority ties oldest-first in /work-items:work

  Tier 3 now picks the first candidate in priority-then-oldest order and
  never one chosen over it on a judgment of impact, scope or type. The
  "Select based on" hints let runs override oldest-first; a preregistered
  pair on #9966 moved the equal-priority case from 0.6 to 1.0 with no
  loss on the other three cases. Adds those four cases to the suite.
