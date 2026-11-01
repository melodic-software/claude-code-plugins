---
bump: minor
---

### Added

- work-item tracker: an `add-recurrence <id> --source-link <url> --note <text>` seam verb records that a signal was seen again on an item, and writes nothing when the item already records that source link, so a lane that sees one signal twice records it once (#11866). The `github` and `local-markdown` adapters implement it; an adapter that does not declare it exits `6`.
