---
bump: minor
---

### Added

- `babysit_review_evidence.bind()` turns a pull request's AI review lane runs, attempts, completion annotations, reviewed-head marker comments and review threads into per-lane evidence for the unattended merge scorer. A lane binds only when its newest run on the pinned head succeeded on an allowed attempt (a second attempt only after a usage-limit failure, else `rerun-not-allowed`), its job left one completion record for that head, an incremental review chains back to a whole review (`incremental-gap`), a `skip=no-change` names a reviewed head one hop away, and the newest marker names the head. Open findings count every summary finding reported over every completed, non-skipped run plus Claude App inline threads open or resolved by a non-human; findings below inline is `count-inconsistent`. Anything doubtful is unbound.
- `fetch_review_threads` returns each thread's `resolvedBy` actor.
