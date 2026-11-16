---
bump: patch
---

### Fixed

- The `lists-citation` graders of the `rd-audit-lists-gone-record` and
  `rd-reversal-asks-before-retiring` eval cases no longer accept a line range or list that starts at
  the citing line (`cookie_store.py:1-2`, `schema.graphql:1,2`). The sweep lists the one citing line,
  and a drop proposal on a range would also edit a line that cites nothing.
- The `asks-before-retiring` grader now accepts an ask that names the retirement as a past
  participle ("Mark ADR 0002 as superseded by ADR 0003?", "it would be set to superseded by 0003 …
  Should I update it?"), as a present-tense verb ("This deletes 0002; go ahead?"), or as "needs your
  yes" with no question mark. It still rejects a report of a finished retirement that ends in an
  unrelated question.
