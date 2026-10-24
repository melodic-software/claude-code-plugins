---
bump: patch
---

### Changed

- A lane escalation's `needs-human` no longer stops the other fixers that could clear its cause. `resolve-conflicts`, `apply-conflict-patch`, `fix-ci`, `apply-patch` and `fix-docs` drop `needs-human` from their `labels-absent` (they keep `do-not-merge`); their dispatchers and base-code jobs (`resolve-conflicts-select` and `fix-docs-head` through the new `lane-hold.mjs`, and `fix-ci-context`) hold the human-gated label unless `gate-source.mjs` reads it as a lane escalation whose reasons, from report-escalation's `- Reason:` line, are another activity's. A person's label, a person's comment since the label went on (as `clear-escalations.mjs` reads one), a review-lane hold or anything ambiguous still holds as `awaiting-human`. The dispatchers read a held PR's timeline once per run between them, and fix-docs reads it only for a PR not yet refined. When they work past the label, the write runner's `patch-fix-requested` lifts only the human-gated hold for that push, under any patch row. The label stays on, so `pr-merge` still refuses the PR.
- `report-escalation.sh` is idempotent per resume key and reason: a second activity escalating on the same head while the label is on posts its own comment, so that activity's own escalation holds it.

### Fixed

- A failed `pr-unblock / resolve-conflicts` run no longer marks its head handled for good: the dispatcher retries it until `limits.limit-stops-per-head` failures (limit stops included) stand on the head.
- A resolve-conflicts run skipped while the pull request was held (`Skipped: awaiting-human`) no longer marks its head handled: the dispatcher skips a held pull request itself, without recording it, and the next sweep after the hold comes off dispatches it. The dispatch record's version is now 4, so heads recorded under the old rule are read again.
- fix-ci no longer leaves a head for good after a run that found no failing check (`not-applicable`) or `fix-ci-restarts` failed runs: once the base tip moves past those runs the dispatcher dispatches the head again, until `limits.limit-stops-per-head` such runs stand on it. A new head starts with none.
