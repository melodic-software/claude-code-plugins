---
bump: patch
---

### Fixed

- `verify:repeated-fail` and `verify:too-old` clear when pr-verify passes a head pushed after the
  last FAIL, and the unarmed comment on such a pull request names that pass instead of saying the
  lanes clear the reason on their own. The Verifier verdict section and the `merge.max-verify-fails`
  description say so.
