---
bump: patch
---

### Fixed

- `lane_eligibility`, the pr-merge lane's gate when it merges lane pull requests itself (not `merge.lane-prs: native`), now applies the trust hold (`trust_refusal`) to the linked issue, as `eligibility` does. A label naming untrusted work, in any spelling, refuses as `untrusted-provenance`; the match on `untrusted` is ASCII-case-insensitive only, as the merge queue's check matches it, so a letter that folds to an ASCII one (`ſ`, `ﬆ`) no longer matches in one and not the other. One removed by a non-human or through an App refuses as `untrusted-provenance-removed-by-non-human`. Unreadable labels refuse as `issue-labels-unreadable`, and a failed timeline read as `unreadable:`. This adds one REST read of the issue timeline per lane pull request with a linked issue. report-outcome already writes a `Hold:` line when the issue carries the exact label at PR open, so this covers a label added after open, or any other spelling.
