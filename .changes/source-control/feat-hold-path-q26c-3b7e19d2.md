---
bump: minor
---

### Changed

- `babysit_risk` splits its path floor by class (`FLOOR_CLASSES`): `HIGH_FLOOR` is now the `trust` and `gate` globs, and an `enforcement` glob (`REVIEW_FLOOR`) scores HIGH as `review-path:<glob>` unless the security lane's evidence is bound to the head with no open finding (`security_review_clean`). A clean code-review lane alone clears nothing. `NEVER_FLOOR_EXEMPT` keeps every floor glob.
- An enforcement path in a pull request that also changes a lane source (a workflow, `CLAUDE.md`, `AGENTS.md`, `.claude/`, `docs/standards/`, `.gitattributes`) scores `review-path-unbindable:<glob>` instead: its security review can never bind at that head, so `person_reasons` names it and it goes to a person. An unbind a later review or read can clear stays the lane's `review-path:`.
