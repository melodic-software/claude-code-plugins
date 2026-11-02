---
bump: minor
---

### Changed

- **babysit-prs**: `babysit_postmerge.py --remediate` files demotion records and suite quarantine issues with no `needs-human` label, and a quarantine issue no longer goes to the suite's CODEOWNERS user. The lanes App files them, so intake triage hands each to a lane. A record's body says how it clears: a schedule or dispatch record once a full run passes on main at a later commit, a canary or read-back record only on a person's direct close.
