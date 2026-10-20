---
bump: patch
---

### Changed

- The work-resolve-issue lane's `report-outcome` no longer writes `Hold: a human merges this` on a `Refs:` pull request, and it holds a diff at the compare-listing cap only while `merge.diff-check.denied-paths` lists a path. A trusted `merge: human` label, structural or untrusted-provenance work, a denied-path match and an unreadable denied-path list still hold the pull request.
