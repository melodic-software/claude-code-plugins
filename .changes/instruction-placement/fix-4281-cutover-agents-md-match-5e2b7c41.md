---
bump: patch
---

### Fixed

- `cutover-check.sh` condition 1 no longer reads a `sub-agents.md` link on a line that mentions a flag as the env-vars page tying `AGENTS.md` to a flag. The "moved bullet" check now matches `AGENTS.md` case-sensitively and as a whole name, so a delisted page grades `[MET]` instead of `[UNREACH]`.
