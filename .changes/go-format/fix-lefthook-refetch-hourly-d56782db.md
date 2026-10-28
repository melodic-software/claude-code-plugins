---
bump: patch
---

### Changed

- The `remotes:` entry `install.mjs plan --scope remote` writes into a consumer's `lefthook.yml` now sets `refetch_frequency: 1h` instead of `24h`, so a hook fix merged to `main` reaches each clone's commits and pushes within an hour. A consumer that already committed the entry keeps `24h` until it edits the line.
