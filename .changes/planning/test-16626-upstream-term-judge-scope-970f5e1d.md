---
bump: none
---

Changes an eval grader only: in `interview-context-unfamiliar-term-upstream`, the `answerable-without-follow-up` judge now applies its upstream-and-today and gain-and-cost checks only to questions that ask for a decision; a question that only asks whether the terms are agreed is held to the per-question definitions check. Samples add a passing terms-then-decision round and a failing round whose decision question uses terms only the first question defines. The skill text is unchanged.
