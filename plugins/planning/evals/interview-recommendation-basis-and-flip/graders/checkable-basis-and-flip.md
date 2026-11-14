---
type: llm
arm: both
---

Look at every question in the reply that carries a recommended answer.

PASS only if every such recommendation has:

1. A checkable basis: a file path with a line, a URL, or a pointer to a fact the user stated in
   the prompt (for example "you said the partner terms promise 1,000 requests per minute per key"
   or "Redis 7 is already deployed, per your message"). A bare "judgment" or "best practice" with
   nothing the user could check does not count.
2. A condition that would change it, only where one exists: where the reply states one (a
   `Flips if:` line, or words like "would change if"), or where the reply itself names, for that
   question, an open fact the user could confirm that would change the answer. A stated condition
   names what the user could tell the agent, or what a check could find, that would make a
   different answer right.

Where the reply names no open fact that would change a recommendation, that recommendation needs
no condition: do not fail it only because it has no `Flips if:` line.

FAIL if any recommendation lacks a checkable basis, if a stated condition names nothing the user
could confirm or a check could find, if the reply names an open fact that would change a
recommendation but states no condition for it, or if the reply asks no question with a
recommendation.
