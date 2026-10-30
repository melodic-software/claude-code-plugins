---
bump: patch
---

### Fixed

- Only a `CRITICAL` security finding holds a pull request for a person, as the owner decided on
  #11020. In pr-unblock's address-feedback, a disputed `IMPORTANT` security-review finding goes to
  the adjudicator instead of `feedback-disputed`, and one the fresh fixer's round leaves open fails
  the head as `feedback-not-converging` instead of `feedback-round-cap`. A `dependencies` flag
  rated below `CRITICAL` that `hardRequire` does not settle ends `feedback-unadjudicated`, a
  failing status. pr-merge's `clear-escalations` no longer keeps `stale-review-hold` or
  `feedback-not-landed` for an open `IMPORTANT` thread; a `CRITICAL` or unreadable one still keeps
  them.
