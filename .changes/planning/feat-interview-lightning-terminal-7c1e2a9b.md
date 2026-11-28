---
bump: minor
---

### Added

- `/planning:interview` lightning style: each question prints as a condensed entry (question line, a few-word bold answer, its basis after a dash, the alternatives' letters), major questions tagged, every gate and the full confirmation kept. Turn it on with `lightning` as the first argument word, "lightning", "go lightning" or "speed this up" mid-interview, or the new `interview_style` setting (`standard` default); "stop lightning" turns it off.
- `round.sh show --level lightning` renders a saved round file as condensed entries; the round file keeps every full block, so "more Q<N>" and `/planning:audit-answers` read it unchanged.
