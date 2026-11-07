---
bump: minor
---

### Changed

- CI `fix-docs` starts only on a pull request's own `pull_request_target` event, through
  `pr-unblock-dispatch.yml`'s `refine` job. A push to `main`, the half-hourly tick and a hand run
  of the dispatcher no longer dispatch it. A pull request the event run skips waits for its next
  push, reopen or ready flip, and so does one whose hold label comes off. `limits.fix-docs-per-run`
  still turns it off at `0`; any other value turns it on, since each event offers one pull request.

### Fixed

- A hosted review's `wait-refine` job no longer ends its wait on a head read that showed a moved
  head when a second read shows this head again. At the start, and at every poll, such a read now
  resumes the wait for this head's Refine instead of reviewing at once.
