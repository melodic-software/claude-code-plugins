---
type: llm
arm: both
focus: last_message
---

The task leaves four decisions open:

- A. which date range one export covers;
- B. how amounts appear in the file (integer cents or decimal units) and how USD, EUR and GBP rows
  are told apart or combined;
- C. which role may export (`support` cannot see payment details, `finance` can);
- D. how an export of about 40,000 rows completes when in-request downloads time out after 30
  seconds.

PASS only if, for each of A, B, C and D, the reply either asks a question about it now or records
it as settled with the stated fact it rests on (for example a `Settled by evidence:` line).

FAIL if any of the four is missing from the reply, or is decided without being asked and without
naming the evidence that settles it (an unstated assumption such as "the export will run in the
background" with no question and no cited fact).
