---
bump: none
---

Removes redundant `testing` eval cases: `tv-reduce-expected-has-no-source`, `run-e2e-app-control-absent-reports-drift`. Each one's behavior is checked by a kept case, or its only
grader was an unlabeled judge, which counts as no evidence. No skill behavior changes.
