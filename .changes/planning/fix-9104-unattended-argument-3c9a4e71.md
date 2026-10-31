---
bump: minor
---

### Added

- `/planning:plan` and `/planning:draft-goal-condition` take an optional leading `unattended` argument. With it, the run records its native offer (`/plan`, or the paste-ready `/goal` line) in its output instead of asking; without it, the run asks. Both argument hints list it.

### Changed

- `/planning:plan`'s argument hint writes its first slot as `[task description|review|close-out]`, so the hint stays within the 100-character budget with `[unattended]` added.
