---
bump: none
---

### Fixed

- The `s1-branch-start-build`, `s4-migrator-build`, `s7-act-after-yes` and `t4-apply-migrate` eval cases chain their `turn-1.jsonl` history records with `uuid` and `parentUuid`, so a resumed case keeps the first-turn request instead of only the last record.
