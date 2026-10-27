---
bump: patch
---

### Added

- A `/testing:write` invocation probe set (`probes/write.json`), weighted toward feature requests
  that ask for tests in passing: the k36-cart-total natural-phrasing case fired the skill in 0 of
  16 runs.

### Fixed

- The k36 `refactor-after-green` grader now reads a Bash command with a double quote before the
  redirect or `sed -i`, such as `sed -i "s/a/b/" cart.py` or `printf "x" > cart.py`, with
  samples for both and for two quoted near-misses.
- The k36 `no-zero-assertion` grader now says why it approximates the `/testing:audit` scan: no
  `claude plugin eval` grader type runs a script, and the scaffold runs before Claude starts.
