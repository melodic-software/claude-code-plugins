---
bump: minor
---

### Changed

- A counted `fail` at an earlier head of a pull request refuses `verify:earlier-fail` unless a `fail` artifact cannot be read, or counted `pass` or `pass-notes` verdicts at the current head, whose runs all started after every such `fail`'s run, clear it; those passes then decide. `merge.skip-unchanged` no longer skips a `verify:earlier-fail` while a PASS artifact names the head.
