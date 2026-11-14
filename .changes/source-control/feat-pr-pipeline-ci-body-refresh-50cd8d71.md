---
bump: minor
---

### Added

- `comments --ci`: the review-thread tool gains `sections`, the PR body sections the round may refresh, and `record-body <file>`, which records their new text once per round. The reply job puts the text in place after the fix lands, and drops it when it holds a line a gate reads. `pr_body_refresh` in `docs/conventions/source-control.yaml` now also governs these rounds.
