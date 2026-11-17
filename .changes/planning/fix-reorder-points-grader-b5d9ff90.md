---
bump: none
---

Changes an eval grader only: in `plan-reviewer-cut-medium-reorder-points`, the `out-of-scope-cut` regex now excuses a phase bullet naming `weekly_report` only when a cut word opens it or a cut label (including `unchanged`) ends it, instead of when "no", "not" or a similar word appears anywhere in it. Samples add two failing bullets that build the report and contain an incidental "no" or "not", and a passing `Out of scope: weekly_report` bullet. The skill text is unchanged.
