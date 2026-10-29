---
bump: minor
---

### Added

- The babysit merge gate reads `merge.diff-check.path-holds` in the pr-merge lane. Absent or
  false, the `high-path:` floor and configured globs and the `review-path:` holds move out of
  the risk score into the gate report's `risk.pathHoldsSkipped`. True keeps them. Unsafe or
  aliasing paths (`high-path:**`), the manifest review and cost holds still hold. The local
  babysit lane keeps every path hold.
