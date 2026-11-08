---
bump: minor
---

### Changed

- `/work-items:work` and the work-loop lane read each candidate's priority from the org `Priority` issue field, falling back to its `priority:` label so items without a field value keep their rank. `work_priority_order` no longer needs the `priority:` form: an entry may name a field option such as `high`, compared case-insensitively.

### Fixed

- The `get-statuses` verb honors `--field` for every field but `Work status` under `config.github.status_trust`; it used to return the Work status regardless of the field asked for.
