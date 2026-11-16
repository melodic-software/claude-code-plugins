---
bump: patch
---

### Fixed

- **`/planning:interview`, terminology matrix.** The matrix question no longer stands in for
  another question's definitions: every question, round 1's included, defines inline each term it
  relies on.
- **Eval `interview-context-unfamiliar-term-upstream`.** The prompt states the quality bar, so
  round 1 asks no bar question that could not show what upstream does.
