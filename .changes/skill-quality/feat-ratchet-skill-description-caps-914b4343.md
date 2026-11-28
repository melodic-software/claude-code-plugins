---
bump: minor
---

### Changed

- Lowered `check-skill.sh` check 30 default `description_warn` threshold from `419` to `350` characters (schema, README, and test suite updated); `description_target` stays `250` and fixed `1,024`-character cap is unchanged.
- Updated `reference/invocation-probes.md` to document the recorded owner-approved exception (#19475 / #19592) under which the three unmeasurable `code-metrics` skills shipped trimmed below `419` characters, noting that frozen probes showed no regression but cannot certify an unmeasurable cut.
