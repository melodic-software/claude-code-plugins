---
bump: patch
---

### Fixed

- `babysit_postmerge.py --remediate` now turns off native auto-merge on every open pull request into the judged branch that the agent identity both opened and armed, before it dequeues the identity's merge-queue entries, so GitHub cannot enqueue an armed lane pull request after a demotion. A pull request a person armed, or one the identity did not open, stays armed. Its report lists them as `disarmed`, and a failed read or disarm is a `disarm:` error that does not stop the dequeue or the demotion issue.
