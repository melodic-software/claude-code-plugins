---
bump: patch
---

### Fixed

- pr-refine holds through a failed read instead of losing the PR. A `fix-docs` handoff read that
  stays unknown prints a notice, starts no fallback and ends green, after at most 3 failed reads.
  `fix-docs-dispatch.mjs` dispatches a PR again after a red run with no check, or a run that held on
  that read, up to `limits.limit-stops-per-head` such runs.
- `handoff-evidence.sh` draws each wait at random from 0 to its cap, for every lane, and keeps
  reading at the last cap until the waits reach the caps' sum.
