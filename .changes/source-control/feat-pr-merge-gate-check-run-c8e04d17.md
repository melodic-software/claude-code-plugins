---
bump: patch
---

### Fixed

- The pr-merge lane's verify escalation comment keeps the last fail summary it quoted when a verdict
  record cannot be read, and carries it into a `verify:earlier-fail` escalation after a push, under
  the head it was given at, so an intermittent download no longer rewrites the comment and the
  reason is not lost. An earlier-fail whose last quote is a fail at this head stays `verify:fail`.
