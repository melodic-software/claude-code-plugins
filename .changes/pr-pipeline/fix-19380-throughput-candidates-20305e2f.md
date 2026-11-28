---
bump: patch
---

### Fixed

- Signal 8 (`throughput-zero`) in `maintenance-monitor-signals` now counts open, non-draft, unheld pull requests authored by `merge.agent-identity` from the existing open-PR GraphQL listing instead of relying solely on `pr-merge`'s `sweep.candidates`, preventing false `throughput-zero` alerts when only non-lanes pull requests are open (falling back to `sweep.candidates` only when the 40-PR listing is truncated with none seen).
