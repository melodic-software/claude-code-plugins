---
bump: patch
---

### Fixed

- The `pull-request-ready-hands-pr-to-explain-change` eval case loads under `claude plugin eval`: it lists a one-file `review-stub` plugin inside the case directory in place of `../../../review`, which the CLI refused as outside the containment root. The stub registers `/review:explain-change` so the hand-off resolves; the review plugin's source is not copied.
