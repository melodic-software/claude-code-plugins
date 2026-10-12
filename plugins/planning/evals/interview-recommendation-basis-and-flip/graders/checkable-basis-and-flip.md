---
type: llm
arm: both
---

Look at every question in the reply that carries a recommended answer.

PASS only if every such recommendation has both:

1. A checkable basis: a file path with a line, a URL, or a pointer to a fact the user stated in
   the prompt (for example "you said the partner terms promise 1,000 requests per minute per key"
   or "Redis 7 is already deployed, per your message"). A bare "judgment" or "best practice" with
   nothing the user could check does not count.
2. The condition that would change it: what the user could tell the agent, or what a check could
   find, that would make a different answer right.

FAIL if any recommendation lacks a checkable basis or a condition that would change it, or if the
reply asks no question with a recommendation.
