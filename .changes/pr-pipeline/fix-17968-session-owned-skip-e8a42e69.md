---
bump: minor
---

### Added

- The lanes skip an issue a local Claude Code session owns. `check-born-triaged`'s routing labels (`routingLabels`, `routingLabel`) now include the work-items binding's session-owned role label (`tracker.config.role_labels["session-owned"]`, default `session-owned`) beside the container label and the wayfind prefix, so intake triage, the hourly triage sweep, intake re-entry, the WIP cap, the issue lane's admission (`check-blockers.mjs`) and the unblock sweep (`label-unblocked.mjs`) leave such an issue alone. A non-string value is a config error that keeps the defaults with a warning. The skip notices now read "a container, wayfind or session-owned label, so the skill or session that filed it routes it".
