---
bump: patch
---

### Fixed

- read a cut-short artifact listing again after every wait, as a 5xx is

  The verify-evidence reader read a whole listing cut short (`unexpected end
  of JSON input`) once more at most, so two cut-short reads in a row refused
  the pull request with `verify:unreadable`. It now reads it again after each
  listing wait while time is left, and a page body cut short while gh exits 0
  (`page N is not JSON`) or that the reader cannot parse counts as cut short
  too. A rate-limit answer is still never read again, and a listing that
  keeps failing still refuses.
