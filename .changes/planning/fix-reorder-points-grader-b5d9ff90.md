---
bump: none
---

Changes an eval grader only: in `plan-reviewer-cut-medium-reorder-points`, the `out-of-scope-cut` regex now excuses a phase bullet naming `weekly_report` only when a cut word opens it, a cut label (including `unchanged`, optionally after a closing parenthesis) ends it, it says the report is `not touched`, `not changed` or similar, or a negation or preservation phrase (`do not`, `never`, `no change to`, `leave`, `without changing`) opens it with no later `:` or `;` clause. Before, any bullet holding "no", "not" or a similar word anywhere was excused; every bullet excused now was excused before. Samples add failing bullets that build the report with an incidental "no" or "not", after an opening negation clause, or under an inflected `Cuts`, and passing bullets that cut or preserve the report. The skill text is unchanged.
