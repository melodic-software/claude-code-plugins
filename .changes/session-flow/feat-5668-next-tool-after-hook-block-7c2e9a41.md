---
bump: minor
---

### Added

- `/session-flow:audit-friction` records which tool follows each hook-block denial. The session scanner adds `next_tool` (the next tool call in the same transcript file, `None` when none follows) and `next_ok` (whether that call succeeded) to each hook-block denial event, and `friction.py mine` tallies `next_tool` per event key and side, with ok, failed and unknown counts, in both the JSON and the markdown output. Sessions collected before this change carry no such field. The tally reads stored events, so a session past the per-session event cap contributes only the events it kept.
