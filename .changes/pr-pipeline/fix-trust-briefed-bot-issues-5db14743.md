---
bump: minor
---

### Changed

- pr-verify takes the body of an issue the lanes App filed as its spec once intake admission has briefed it and a listed human has not vetoed it (the owner's standing rule, 2026-11-22). Briefed: the lanes App's newest admission record (`<!-- issue-admission-record -->`, by its account id, canonical and never edited) names the issue's current title and body by hash. Vetoed: a listed human holds the issue at `needs-owner-decision` or `needs-human`, or its body carries a `hold:` line. An outsider's comment with the marker, an edit after the record, or a hold set by a person keeps the body out of the spec.
