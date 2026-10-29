---
bump: patch
---

### Fixed

- `clear-escalations.mjs` takes off a `needs-human` the lanes App set for `feedback-not-landed` once the head is none of that escalation's resume keys and no unresolved review thread carries a lanes App comment. It pages the PR's review threads over GraphQL, and a listing that may be cut short keeps the label. A person who commented or reviewed since the label went on still keeps it. The monitor's stalled-stop signal does not count that clear as a stop standing on the head.
