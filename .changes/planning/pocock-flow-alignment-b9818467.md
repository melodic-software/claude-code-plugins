---
bump: minor
---

### Changed

- `/planning:interview` no longer gates a change whose diff is quick to review and cheap to retry; behavior change alone does not force it, and its description triggers before work whose diff fails either test. A new effort starts at the interview however big, and the user can run `/planning:wayfind` in the same session when it outgrows one.
- `/planning:wayfind` is an escalation from an interview, never the first step: its description says so, and chart mode, after the no-fog bail-out, sends an effort with no interview behind it to `/planning:interview` first. Charting seeds the map from an interview ledger: settled answers go into one seed decision item with one Decisions-so-far pointer, and open questions become decision items. It gains a `## Next` section.
- `/planning:plan` sends a too-big, foggy effort to `/planning:wayfind` only after an interview outgrew one session, else to `/planning:interview` first.
