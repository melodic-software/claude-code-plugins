---
bump: patch
---

### Fixed

- babysit-prs: a push that changes `plugins/code-metrics/scripts/**` or the code-metrics audit skill's scripts now stops an approval from carrying (`CARRY_REFUSES`), since CI's size check runs them.
