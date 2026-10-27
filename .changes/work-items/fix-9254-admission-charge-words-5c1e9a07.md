---
bump: patch
---

### Changed

- `rule-admit.sh` reads its charge words from `scripts/charge-words.json`, the one definition
  intake admission reads too, and exits 8 when that file is unreadable.
