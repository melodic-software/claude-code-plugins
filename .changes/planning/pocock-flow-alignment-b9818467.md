---
bump: minor
---

### Changed

- `/planning:interview` no longer gates a change whose diff is quick to review and cheap to retry; behavior change alone does not force it. A new effort starts at the interview however big, and the user can run `/planning:wayfind` in the same session when it outgrows one.
- `/planning:wayfind` is an escalation from an interview, never the first step: chart mode sends a brand-new effort to `/planning:interview` first, and seeds the map from an interview ledger, charting settled answers as closed decisions and open questions as decision items. It gains a `## Next` section.
