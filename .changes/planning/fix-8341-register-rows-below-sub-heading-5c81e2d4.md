---
bump: patch
---

### Fixed

- `check-open-questions.sh` no longer grades a register clean while question rows sit below a sub-heading inside it. Any unfenced `- Q<N> |` row outside the `## Open-question register` section now makes the ledger ungradeable (exit 2), and stderr names each such row's line. Rows inside a fenced block are still documentation. The `/planning:interview` ledger template now says to keep live rows above any heading in the register.
