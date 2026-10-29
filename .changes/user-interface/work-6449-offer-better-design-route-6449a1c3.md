---
bump: minor
---

### Added

- `/user-interface:design` offers to install a better route for a concern: the highest-ranked row
  that is not installed, not `deferred`, and fits this platform and the account rules. It offers a
  `paid` row only when no free row covers the concern. It gives the row's `pointer` URL as the
  source of the install and sign-in steps, says when the team file supplied the row, and installs
  at local scope only after the user says yes to the exact command; otherwise it continues with the
  best route already present. Three eval cases cover the offer, a decline and an accept.
