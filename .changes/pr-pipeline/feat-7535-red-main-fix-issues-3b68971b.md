---
bump: minor
---

### Added

- post-merge-demotion-alert.yml files one fix issue per newly failing check of a red scheduled or
  dispatched full run on main, at most 5, beside the new demotion or failure record, and dispatches
  intake triage for each. The issue holds fixed text only (a check name in a checked charset, hex
  SHAs, the run link and the record number), carries no label, and is reopened when its check
  fails again. The record keeps `needs-human`; closing a fix issue changes nothing on it.
