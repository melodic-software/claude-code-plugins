---
bump: minor
---

### Changed

- CI `fix-docs` starts only on a pull request's own `pull_request_target` event, through
  `pr-unblock-dispatch.yml`'s `refine` job. A push to `main`, the half-hourly tick and a hand run
  of the dispatcher no longer dispatch it. A pull request the event run skips waits for its next
  push, reopen or ready flip, and so does one whose hold label comes off. `limits.fix-docs-per-run`
  still turns it off at `0`; any other value turns it on, since each event offers one pull request.
