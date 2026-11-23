---
bump: none
---

Removes redundant `fleet` eval cases: `reach-same-repo-session-picks-lane`. Each one's behavior is checked by a kept case, or its only
grader was an unlabeled judge, which counts as no evidence. No skill behavior changes.
