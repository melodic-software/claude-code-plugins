---
bump: none
---

Changes an eval grader only: in `plan-reviewer-cut-medium-reorder-points`, the `out-of-scope-cut` regex now excuses a phase bullet naming `weekly_report` only when a cut word opens it, a cut label (including `unchanged`) ends it, or a negation or preservation phrase (`do not`, `never`, `leave`, `keep` and similar) opens it with no later `:` or `;` clause, instead of when "no", "not" or a similar word appears anywhere in it. Samples add failing bullets that build the report with an incidental "no" or "not", or after an opening negation clause, and passing bullets that cut or preserve the report. The skill text is unchanged.
