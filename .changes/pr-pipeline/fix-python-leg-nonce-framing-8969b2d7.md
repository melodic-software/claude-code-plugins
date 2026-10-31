---
bump: patch
---

### Fixed

- `test-python`'s suite step prints a per-run nonce, repeats it in each suite's call line, and
  prints an exit line carrying it after each suite. The post-merge demotion judge reads only those
  lines, so a suite's captured output cannot move a failure onto another suite. The nonce sits in
  a variable no suite inherits.
- The quarantine rule in the convention README states the non-determinism evidence a repeat failure
  needs, and that a token without `Actions` read cannot name a suite, so the failure demotes.
