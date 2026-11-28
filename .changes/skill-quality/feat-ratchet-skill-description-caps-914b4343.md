---
bump: minor
---

### Changed

- Lowered `check-skill.sh` check 30 default `description_warn` threshold from `419` to `350` characters (schema, README, and test suite updated); `description_target` stays `250` and fixed `1,024`-character cap is unchanged.
- Updated `reference/invocation-probes.md` to record the Opus-era description-only control result as historical measurement context rather than a blanket freeze on trimming `> 419`-character descriptions.
