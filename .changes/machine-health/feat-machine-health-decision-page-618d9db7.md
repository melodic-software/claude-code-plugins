---
bump: minor
---

### Added

- Each audit run builds a decision page, `<StateBase>/views/checkup-<runStamp>.html`, with the shared view builder: every check's items, worst first, a "Mute this item" pick on each item that has a stable key, a pick per remediation, a note field, and a button that copies the picks. Machine-derived text reaches the page only as data rendered as text. The page sits beside its data and an id map, and the report's new "Decision page" section names it. Only the newest 12 runs' pages are kept; older ones are deleted by their exact paths after a successful build. Without Node.js the run logs `checkup_view_skipped node_missing` and the report says no page was built.
- `/machine-health:setup picks` resolves a pasted payload against the id map of the run its `run:` line names. It refuses the whole payload when that line is missing or the map is gone, refuses any pick the map does not hold, lists the rest with the run's time, and writes mutes after one yes (with "drop N, M") and each approval after its own yes, through `Set-ApprovalState`.
- Setup `check` validates `state/mutes.json`: its schema, the key shape, the key's kind and the check id.

### Changed

- The `node` prerequisite's degrade text now says that without Node.js no decision page is built.
