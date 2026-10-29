---
bump: patch
---

### Fixed

- A fix-ci run whose only fix weakened a test no longer hands the pull request to a person on the
  head's first fix-ci attempt. apply-patch stops it as `ci-fix-weaken-retry`, a failing status,
  and the fix-ci dispatcher retries the head once at `model-rung` 1. That fresh fixer round's
  `context.json` carries a fixed `retry` brief (keep every test's assertions; change an expected
  value only when the behavior change the pull request states requires it, and say why on the
  report line) and the pull request's title and body. `fix-ci-context` decides the round
  (`weaken-retry`: no finished fix-ci check and no lane stop on the head) and finds it again from
  the head's `Lane stopped: ci-fix-weaken-retry` status. A `weaken-required` in that round, or
  after any earlier attempt on the head, still goes to a person as `ci-fix-weaken-required`, and a
  `protected-path` escalation beside it still wins.
