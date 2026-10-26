---
bump: minor
---

### Added

- A review lane's own `critical-security` hold comes off once that lane's complete review of a newer head finds no CRITICAL finding and no open IMPORTANT security finding (owner decision Q15 (a), 2026-10-26). ci-status's new `Clear a review-lane security hold its lane re-reviewed clean` step removes the label with one comment naming both heads, judged by the base's `merge-holds.mjs` `laneLift`: only a label `github-actions[bot]` (matched by numeric id) added right before a held review comes off, and a person's or another lane's label, a cost hold, an incomplete or errored review, an open finding above SUGGESTION and anything unread keep it. The hold-lift check skips while the lift holds.
