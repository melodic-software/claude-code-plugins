---
bump: minor
---

### Added

- `/user-interface:design` offers to install a better route for a concern: the highest-ranked row
  that is not installed, not `deferred`, and fits this platform and the account rules. It offers a
  `paid` row only when no free row covers the concern. It points to the row's `pointer` for the
  install and sign-in steps and installs at local scope only after the user says yes; otherwise it
  continues with the best route already present. Three eval cases cover the offer, a decline and
  an accept.
