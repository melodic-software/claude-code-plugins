---
bump: none
---

Removes redundant `x` eval cases: `read-tracking-params-dropped-by-rebuild`. Each one's behavior is checked by a kept case, or its only
grader was an unlabeled judge, which counts as no evidence. No skill behavior changes.
