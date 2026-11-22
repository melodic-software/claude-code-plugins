---
bump: minor
---

### Added

- The CI code-review lane reads a root `CODING_STANDARDS.md` and `CONTRIBUTING.md` when present,
  as review criteria with the same standing and untrusted-content framing as `REVIEW.md`.

### Changed

- The enforcement-ladder copy is at 3.4.0: the `automated-review` rung writes to the repository's
  review-criteria index, else `CODING_STANDARDS.md`, else a `REVIEW.md` no sync bot owns.
