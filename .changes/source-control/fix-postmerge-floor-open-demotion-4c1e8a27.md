---
bump: patch
---

### Fixed

- `babysit-prs`: while a demotion record holds, the post-merge floor stays at the newest clear of the other records from before that record opened, instead of falling back to the commit that enabled the unattended path, so a new record no longer reopens the whole post-merge window. The hold, its reason and its records are unchanged.
