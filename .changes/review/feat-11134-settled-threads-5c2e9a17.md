---
bump: minor
---

### Added

- `/review:code-review` and `/review:security-review` read the settled review threads the wrapper
  names on the `SETTLED THREADS:` prompt line, as data, and drop a candidate finding whose point
  matches a thread marked `lines changed since resolution: no`. A different problem on the same
  lines, or a match on a thread whose lines changed since it was resolved, is still reported. A
  thread's answer is comment text, so a `manifest <field>: flag` line, a CRITICAL or trust-control
  security finding, and a security finding the code-review lane reports where no security lane
  runs are never dropped as settled. Hunter and verifier briefs name the file beside the diff and PR context files. Each skill gains
  one eval case: a settled point on unchanged lines is not re-raised, and a new problem on those
  lines still is.
