---
type: llm
arm: both
---

Read the reply as a person who has never seen this repository or the upstream triage tool and
knows only what the reply says.

PASS only if every question in the round can be answered by that person without asking a follow-up
question first. For each question, check that it:

1. Defines, in the question itself, every term it relies on that such a reader may not know,
   including "dedupe fingerprint" (upstream's hash of the normalized first error line) and the
   cluster step, wherever the question uses them.
2. Says what the upstream README does or ships and what the repository has today (every report
   opens its own issue in triage/intake.py), so the gap is visible.
3. Gives each alternative what it would gain and what it would cost.

Checks 2 and 3 apply only to a question that asks for a decision about the change. A question that
only asks whether the reader agrees with the terms' definitions is held to check 1 alone.

FAIL if any question leaves the reader to ask what a term means, if a decision question leaves the
reader to ask what upstream does or what exists today before they can answer, if a question's
needed context sits only in another question or in an earlier summary, or if the reply asks no
question.
