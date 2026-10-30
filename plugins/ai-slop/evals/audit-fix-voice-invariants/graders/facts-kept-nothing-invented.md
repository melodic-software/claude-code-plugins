---
type: llm
arm: both
focus: { source: file, path: docs/build.md }
---

The original docs/build.md said: the old build ran on three runners; the cache may have
been out of sync between them, which may explain the flaky tests (the original put two hedges on
each half of that claim); moving
to one runner cut the median build from 14 minutes to 9; the cost is that two builds now queue
behind each other at peak hours; then a chat sign-off.

PASS only if the rewritten file (1) still states the three runners, the cache-sync explanation
for the flaky tests with at most one hedge on it, the median build going from 14 minutes to 9,
and two builds queueing at peak hours; (2) adds no number, person, team, tool, quote, source or
claim that the original did not hold; and (3) contains no misspelling or deliberate typo. FAIL if
any listed fact is missing or changed, if the explanation is now stated as certain, if anything
new is asserted, or if a word is misspelled.
