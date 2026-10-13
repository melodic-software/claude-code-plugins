---
bump: minor
---

### Added

- `/harness-ops:lanes` `start`, `restart` and `status` print a `mods:` line under each lane. It reads `off` with the cause the launcher can see (a CLI below the mods version floor, `disableAllHooks` in the lane's `settings`, or what `claude plugin test` reports from the repo), `unknown` when the launcher cannot tell (including a probe that does not answer within its timeout), and `can load` only when nothing it sees stops mods. A lane whose mods cannot load runs context-guard and rate-limit-guard reactive-only, and nothing said so before.
