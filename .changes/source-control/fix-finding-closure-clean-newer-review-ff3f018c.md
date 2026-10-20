---
bump: patch
---

### Fixed

- pr-merge's open-findings count closes a resolved review thread, whoever resolved it, once the lane's review of the current head completed after the thread was opened and no review of that head reports a finding, so a clean incremental review on top of a whole review that reported findings now clears them. Closure stays per lane: a security-lane (HIGH) finding needs the security lane clean on the head. A clean review of another head, an unresolved thread, or a finding another review of the same head reported still keeps it open.
