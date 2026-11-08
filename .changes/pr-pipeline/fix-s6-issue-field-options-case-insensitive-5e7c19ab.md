---
bump: patch
---

### Fixed

- Every writer of the Size, Complexity and Uncertainty issue fields now sends the option's lowercase name and falls back to Title case when GitHub refuses it, so the org can rename those options to lowercase without breaking the intake digest or post-merge record writes. Intake triage and the digest write one field at a time while part of the rename has landed; the post-merge record write only warns until the rename is done.
