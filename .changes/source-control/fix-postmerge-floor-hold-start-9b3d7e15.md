---
bump: patch
---

### Fixed

- `babysit-prs`: while a demotion record holds, the post-merge floor stays at the newest clear of the other records from before that record opened, so a clear made later no longer moves the floor past the merge the holding record cites. A read failure after a hold is found keeps the hold instead of escaping.
