---
type: regex
pattern: '^Refactor checkpoint:'
flags: m
---

Passes when the final reply holds a line that begins `Refactor checkpoint:`, the report the skill
writes after green when `tdd_refactor_step` is `on`. A bulleted or bolded line does not count.
