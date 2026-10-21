---
bump: minor
---

### Added

- post-merge-demotion-alert.yml files one fix issue per newly failing check of a red scheduled or
  dispatched full run on main, at most 5, beside the new demotion or failure record, and dispatches
  intake triage for each. The issue holds fixed text only (the failing job's name in a checked
  charset, never an annotation title, hex SHAs, the run link and the record number), carries no
  label, is locked before intake reads it, and is reopened when its check fails again. A fix issue
  that could not be filed, locked, reopened or sent to intake is named in a comment on the record.
  The record keeps `needs-human`; closing a fix issue changes nothing on it.
