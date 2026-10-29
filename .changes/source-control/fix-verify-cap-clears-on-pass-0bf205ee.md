---
bump: patch
---

### Fixed

- pr-merge's gate no longer holds a pull request for good on `verify:repeated-fail` or
  `verify:too-old`. The cap still holds while FAILs keep coming. A pr-verify pass at a head with
  no FAIL, every pass run created after every counted FAIL run at the capped heads, ends it, and
  the other verifier rules then decide. An old pull request is judged on its verdicts and refused
  `verify:too-old` only when they would not allow it, and never in place of a refusal a person
  must clear. The skip-unchanged re-gate judges both again while a PASS artifact names the head.
