---
bump: minor
---

### Added

- `/session-flow:audit-sessions`: the `tools.denials` finding now counts denials per kind over the sessions above the threshold (`by_kind`) and names the most common kind (`dominant_kind`), in both the JSON and the markdown report. The rule's basis says how the kinds are read from the store, with an As of date and a recheck trigger (#10812).

### Changed

- `/session-flow:audit-sessions`: the `subagents.count` finding now suggests `/harness-ops:observability` with route `retro-codify`, the same as `tokens.sub`, in place of `/harness-config:unhobble`, per the owner decision of 2026-10-11 (#10812).
