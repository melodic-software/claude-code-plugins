---
type: llm
---

The Brief already records three quality requirements under Constraints: the Loqate lookup adds at
most 300 ms to checkout at p95; if Loqate is down or slower than 2 seconds, checkout proceeds and
logs a warning; the full address is never logged.

PASS if the reply treats these as settled inputs (it may cite them or design to them, for example
a timeout or a cache sized to the 300 ms budget) and asks the user no question that re-opens any of
them: not what the latency target should be, not what happens when Loqate is down, not whether the
address may be logged.

FAIL if the reply asks for a performance, availability or logging target or behavior the Brief
already states, offers to change one of those targets as an open question, or contradicts one of
them without naming the conflict.
