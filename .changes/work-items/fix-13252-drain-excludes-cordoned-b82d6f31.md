---
bump: minor
---

### Changed

- `/work-items:work-loop` states that an item in a cordoned milestone does not hold a `--drain` exit, reading the names from `cordoned-milestones` in the target's `admission-rules.json`. It takes effect once the tracker seam's item rows carry a milestone; until then an open cordoned item still holds the drain.
