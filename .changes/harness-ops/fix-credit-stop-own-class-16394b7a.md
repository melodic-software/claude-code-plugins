---
bump: patch
---

### Fixed

- `/harness-ops:morning-brief` prints the `KEY: <role> credit-stop` line for an API-key leg whose lane-outcome record has class `credit-stop`, not only for a run that fell back on one. A key leg that credit-stopped with no fallback leg used to print no KEY line.
