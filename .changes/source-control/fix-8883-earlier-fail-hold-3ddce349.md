---
bump: minor
---

### Changed

- The pr-merge lane no longer holds a pull request for `verify:earlier-fail` once its current head has a counted pass or pass-notes verdict that clears the spec checks: the head's passes then decide, so a changed or untrusted spec still refuses. With no counted pass at the head, or when a read fails, an earlier head's fail still refuses `verify:earlier-fail`, and a fail at the head still refuses `verify:fail`. Skip-unchanged no longer carries a `verify:earlier-fail` refusal forward while a pass artifact names the head.
