---
bump: patch
---

### Fixed

- The pr-merge verdict gate (`babysit_verify_evidence.py`) no longer holds a pull request forever
  once pr-verify has failed it at `merge.max-verify-fails` heads. `verify:repeated-fail` now
  refuses only while a `fail` stands at the head, where it still withholds a further fix round. A
  later head whose pass clears the earlier `fail` verdicts merges as any other passing head does.
