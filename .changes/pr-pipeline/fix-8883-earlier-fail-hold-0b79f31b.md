---
bump: minor
---

### Changed

- A counted `fail` at an earlier head of a pull request refuses `verify:earlier-fail` only while the current head has no counted `pass` or `pass-notes`, or a read fails; otherwise the head's passes decide. `merge.skip-unchanged` no longer skips a `verify:earlier-fail` while a PASS artifact names the head.
