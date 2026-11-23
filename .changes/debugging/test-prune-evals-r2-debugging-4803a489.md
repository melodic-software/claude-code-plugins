---
bump: none
---

Removes redundant `debugging` eval cases: `red-run-crash-on-empty-team`. Each one's behavior is checked by a kept case, or its only
grader was an unlabeled judge, which counts as no evidence. No skill behavior changes.
