---
bump: patch
---

### Fixed

- With `--surface`, `check-open-questions.sh --procedure --brief` now fails a Brief that lost any line the page export writes, in every section but Decisions (which keeps its own count check): a dropped restated Problem, Goal, Constraints, Out-of-scope or Deferred line no longer passes.
- It also fails a Brief whose Constraints hold a `Q<N>` line the export does not write there, such as a Decisions line repeated as a constraint.
