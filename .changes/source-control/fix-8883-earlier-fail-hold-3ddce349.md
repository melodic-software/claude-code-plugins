---
bump: minor
---

### Changed

- The pr-merge lane no longer holds a pull request for `verify:earlier-fail` once its current head has counted pass or pass-notes verdicts whose runs all started after every earlier fail's run, each start read fresh from GitHub: the head's passes then decide, so a changed or untrusted spec still refuses. With no such pass, a missing start time, or an unreadable fail artifact, an earlier head's fail still refuses `verify:earlier-fail`, and a fail at the head still refuses `verify:fail`. Skip-unchanged no longer carries a `verify:earlier-fail` refusal forward while a pass artifact names the head.
