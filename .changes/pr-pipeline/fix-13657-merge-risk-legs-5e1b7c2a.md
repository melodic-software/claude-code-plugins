---
bump: patch
---

### Fixed

- The merge-risk rating (`pr-rate-merge-risk.yml`) now runs on the three legs every model lane runs, one credential per job: the `pr-verify` role's API key, then its subscription token, then the central fallback token, each after the one before hands off or finds its credential empty. The key leg skips a key whose credit stop is recent (`check-key-credit`) and marks a new one. A credit-stopped key no longer leaves the head `unrated`, and a key leg that hands off no longer fails its job.
