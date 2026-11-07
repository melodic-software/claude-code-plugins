---
bump: patch
---

### Fixed

- `intake-reenter` no longer adds `needs-triage` when a listed human releases a Work status hold. It claims the release with a comment marked with the field event that left the hold, so a re-run of that release dispatches nothing and a later release on the same issue dispatches again; a failed run deletes the comment and leaves Work status as written.
