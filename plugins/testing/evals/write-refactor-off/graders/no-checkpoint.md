---
type: regex
pattern: '^Refactor checkpoint:'
flags: m
match: not_contains
---

Passes when no line of the final reply begins `Refactor checkpoint:`: with `tdd_refactor_step`
set to `off` the skill skips the Refactor step and its report. The skill-fired, resolver-ran and
settings-line graders keep an empty or off-task reply from passing on this grader alone.
