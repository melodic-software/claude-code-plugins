---
bump: patch
---

### Fixed

- The PR-body linkage gate no longer times out on a very long line or a long run of trailing newlines. `negation_trigger_to` reads only the last five words before a closing keyword without copying the line once per word (a line of about 27,000 words before `closes #N` passed the 15 s hook timeout, and a timed-out hook does not block), and `linkage::chomp_to` removes the trailing newline run in one step. Verdicts are unchanged.
