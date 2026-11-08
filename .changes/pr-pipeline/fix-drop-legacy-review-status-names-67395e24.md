---
bump: patch
---

### Changed

- The "Both lanes review the head" hold names the status jobs it now reads, `pr-review / review-status` and `pr-review-security / review-status`. A review from a status job under the names pr-review.yml and pr-review-security.yml gave before ci-workflows#866 no longer counts.
