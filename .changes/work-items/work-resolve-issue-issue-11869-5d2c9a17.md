---
bump: minor
---

### Added

- triage: an idea issue, a feature request that does not say what it is for, now goes to `/planning:interview` and is parked with `needs-spec` before any code search, ledger check, verification or research (#11869). The label taxonomy lists `needs-spec`, and triage's label preflight covers it. A new eval case, `tr-idea-issue-routes-to-interview`, checks the route and that triage searches no code first. The tracker's human floor now holds `needs-spec`, so `list-frontier --autonomous` drops a parked idea issue the way it drops `status: needs-decision` and `status: needs-info` items.
