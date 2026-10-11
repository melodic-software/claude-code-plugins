---
bump: patch
---

### Fixed

- The PR-body linkage gates judge a body whose section ends in a long run of blanks in linear time. The old whitespace trim was quadratic, so about 18,000 trailing blanks ran past the 15 s hook timeout and the gate stopped checking that body (#7069).
