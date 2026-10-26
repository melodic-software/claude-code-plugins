---
bump: minor
---

### Added

- `merge.verify-cache` (default `shadow`) sets how enable-auto-merge uses the verifier refusals the last run kept. Each scheduled or hand-started run reads them from the newest trusted run's `pr-merge-verify-answers` artifact (`verify-answers.mjs`, found as the head-ref map is, never through actions/cache) and uploads its own, always, with 1-day retention. Under `shadow` every pull request is still read in full, and each read logs `verify-cache shadow: #<n> key=hit|miss stored=<kind> fresh=<kind> agree=yes|no|n/a`. Under `serve` an unarmed pull request whose kept refusal still matches is left unarmed on it with no further read, and is answered only from a kept refusal once the read budget is spent. An armed pull request is always read in full. A kept answer that holds nothing is read again in full and never arms. A kept refusal writes no new comment or label unless its reason changed. Each cost line shows `cached=0|1` when the answers files are in use.
