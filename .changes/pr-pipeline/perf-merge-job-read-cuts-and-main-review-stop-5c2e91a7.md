---
bump: minor
---

### Changed

- pr-review-main records a designed stop instead of failing. A diff that holds a binary file, is
  over the 300000-byte cap, or has a line over 1800 bytes leaves the leg green with no verdict.
  The record job then posts the check run `pr-review-main: <lane>` on the head, titled
  `verdict=none reason=<too-large|binary|long-line>` with conclusion neutral, and logs a
  `pr-review-main stop` notice. Each stop is one countable record, and a real failure (a failed
  fetch or diff write, an empty diff) still fails the run.
