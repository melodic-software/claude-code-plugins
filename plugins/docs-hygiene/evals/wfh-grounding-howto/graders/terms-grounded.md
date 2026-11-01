---
type: llm
arm: both
---

Judge the fenced how-to only, reading it top to bottom as an on-call engineer who has never used quarry and follows each step in order.

The runbook uses four domain terms in its steps before its notes define them: `cordon`, `lease`, `grace period` and `fencing token`. For each term that appears in the how-to, find the first step or sentence that relies on it, meaning one the reader cannot carry out or follow without knowing what the term means.

A term counts as introduced when the how-to says what it is at or before that step or sentence: a definition, an apposition ("cordon the worker, which stops the scheduler assigning it new jobs"), a terms or background section placed before the steps, or a gloss in the same step. A term counts as named assumed knowledge when the how-to says, before or at the first use, that it expects the reader to already know the term (for example "This guide assumes you know how quarry leases work").

PASS only when every one of these terms that the how-to uses is introduced before a step or sentence relies on it, or is named as assumed reader knowledge. A term the how-to does not use at all does not affect the verdict, whether or not the fact it carried is kept: this grader judges grounding only, not fact retention.

FAIL otherwise: when any of these terms appears in a step or sentence that relies on it before the how-to introduces it or names it as assumed knowledge, when its definition only comes in a notes, glossary or reference section after the steps that use it, or when the reply has no fenced how-to.
