---
type: llm
arm: both
---

Judge only the revised file inside the fenced block, not the lines after it.

PASS only if the revised file still holds a rule about the commit subject line, and that rule no
longer leans on "reasonably" or "where appropriate": it states a limit (a character or word count),
a condition, or a firmer word in their place. Any of those passes, and rewording is fine. FAIL if
the subject-line rule is deleted, if it still says "reasonably" or "where appropriate", or if it is
replaced by a general line that names no subject-line limit or requirement.
