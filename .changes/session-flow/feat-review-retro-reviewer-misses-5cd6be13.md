---
bump: minor
---

### Added

- Retro reports a "Reviewer missed it" finding, routed to `/corrections:codify`, and a "Missed or
  hard-to-find skill" finding, routed to `/harness-ops:audit-skill-visibility` or reported as a
  `/session-flow:workflow` step candidate.
- Retro's `## Next` names `/session-flow:recommend-skills`.

### Changed

- The no-op steering-file finding also covers the repository's review-criteria files.
- The enforcement-ladder copy is at 3.4.0: the `automated-review` rung writes to the repository's
  review-criteria index, else `CODING_STANDARDS.md`, else a `REVIEW.md` no sync bot owns.
