---
bump: minor
---

### Changed

- `/harness-config:audit-automation-gaps`'s rule inventory counts `CODING_STANDARDS.md`, the
  review-criteria index `docs/review/README.md` and the `docs/review/` files it links as
  `automated-review` rules, beside `REVIEW.md`.

- The enforcement-ladder copy is at 3.4.0: the `automated-review` rung writes to the repository's
  review-criteria index, else `CODING_STANDARDS.md`, else a `REVIEW.md` no sync bot owns.
