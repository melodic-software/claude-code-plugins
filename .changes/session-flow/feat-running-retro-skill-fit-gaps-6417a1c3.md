---
bump: minor
---

### Added

- `running-retro` checkpoint finds skill-fit gaps with six detectors: a skill bypassed or overridden, the same rules re-typed into several briefs, a worker stalled or re-briefed for the same reason, a denial that forced a workaround, a verifier loop stopped by judgment, and the owner asking whether a skill exists. Each finding names its owning plugin and skill and cites its evidence. Before offering to file, the skill searches the owning plugin's open issues through `/work-items:track search`; skill-fit gaps are never auto-filed.
- Eval case `rr-skill-fit-names-owner`.
