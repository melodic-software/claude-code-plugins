---
bump: patch
---

### Fixed

- retry a demotion's recovery read once and warn when it still fails

  A red-main demotion record's recovery reads (the green-runs listing,
  main's tip and the compares) now retry once on no answer, a timeout
  or a 5xx; a 403 or 429 is left to the rate guard. When the read still
  fails the record holds as before, and the merge policy prints
  `::warning::demotion #<n>: recovery read failed: <error>` instead of
  holding lane merges in silence.
