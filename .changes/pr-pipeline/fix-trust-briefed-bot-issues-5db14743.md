---
bump: minor
---

### Changed

- pr-verify takes the body of an issue the lanes App filed as its spec once intake briefed it and no one vetoed it (the owner's standing rule, 2026-11-22). Briefed: the lanes App's newest admission record (`<!-- issue-admission-record -->`, by its account id, canonical and never edited) names the issue's current title and body by sha256. Vetoed: the issue carries a hold label (`needs-human`, `needs-owner-decision`, `needs-reporter-info`, `needs-spec`) or `provenance: untrusted`, or its body has a `hold:` line (`briefedIssue` in `admit.mjs`). A marker in anyone else's comment, an edit after the record, or a label list that cannot be read whole keeps the body out of the spec.
