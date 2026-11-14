---
bump: patch
---

### Fixed

- The `interview-recommendation-basis-and-flip` eval case now requires a flip condition only where one exists, matching the interview's optional `Flips if:` line; a checkable basis is still required on every recommendation, and a bare judgment basis still fails. Its samples add a passing reply that omits `Flips if:`, a failing reply whose stated flip condition names nothing checkable, and a failing reply that names an open fact but states no condition for it.
