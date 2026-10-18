---
bump: minor
---

### Added

- `/work-items:triage` sizes an item it makes autonomous-eligible when the repository's `docs/conventions/pr-pipeline.yaml` sets `models.issue-sizes`: it applies the configured size label (prefix and size names read from that block) in the same edit as the role label, and routes an item only a `split` size fits to `/work-items:decompose` instead of `agent-ready`. A size label the repository lacks is reported, not a stop.
