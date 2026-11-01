---
bump: patch
---

### Fixed

- **babysit-prs**: the pr-verify verdict reader re-reads the pages around kept artifact-listing entries near expiry even when the listing holds exactly GitHub's live count. An entry GitHub deleted early could stand in for a FAIL the listing skipped, so the count matched and the FAIL was left out. A count those reads cannot settle now refuses instead of allowing; a 5xx that outlasts its waits, a count left unsettled only by the near-expiry read caps, or a listing whose time runs out after those reads began, refuses as transient and is not noted for the job; the last two print a `babysit-listing-miss` line with `cause` `near-expiry-cap` or `near-expiry-deadline`.
