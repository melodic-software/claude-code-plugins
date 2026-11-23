---
bump: patch
---

### Changed

- `/architecture:adr` keeps a short `SKILL.md` hub with an action router; the recording flow, with the admission test, moves to `actions/record.md` and the read-only audit to `actions/audit.md`, next to `actions/prune.md`. `audit` points removal at `prune` instead of offering retirement itself.
- `/architecture:adr`'s admission test fails a decision still provisional on a prototype that has not run, and offers to skip it; the decision becomes eligible once the prototype's verdict confirms it. `audit` applies the same condition to existing records.
