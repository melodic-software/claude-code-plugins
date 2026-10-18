---
bump: patch
---

### Fixed

- The `pull-request-ready-hands-pr-to-explain-change` eval case now loads under `claude plugin eval plugins/source-control`: it ships a stand-in `review` plugin with an `explain-change` skill under `fixtures/review-stub` instead of naming `../../../review`, a path outside the runner's containment root.
