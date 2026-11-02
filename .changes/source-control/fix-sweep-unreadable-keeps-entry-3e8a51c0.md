---
bump: patch
---

### Fixed

- `babysit-prs`: the pr-merge merge job's queued-entry sweep no longer dequeues a lanes App entry just because this run could not read its pr-verify verdict. The merge queue's ci-status reads a lanes App pull request's verdict itself and refuses it fail-closed, so the reader answers `verify:queue-reads` and the entry stays, not counted as kept. Before, when the merge job's whole artifact listing failed, the sweep removed lanes App entries that enable-auto-merge had just armed on a pass, and they cycled in and out of the queue. Every other unreadable entry still leaves, adopted pull requests included, since the queue reads no verdict for them.
