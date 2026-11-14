---
bump: patch
---

### Fixed

- An issue refused only because some, not all, of its done-when items are ones an unattended lane run cannot perform now gets those items split off with no person. When work-unblock's sweep or a person's `admission-deferred` mark writes that refusal, outside an intake run, the issue parks at Work status needs-triage instead of confirmed, with a hand-back comment that starts a new triage-sweep cycle once per body version, so intake triages it and refine.mjs splits those items. refine-select now reads the parked state from the Work status field, which admission writes instead of a label, so the split also runs on an issue intake's own admission parks. A split never lifts a `needs-owner-decision` hold, a cost verdict's included. Before, such an issue sat at confirmed until someone edited its body.
