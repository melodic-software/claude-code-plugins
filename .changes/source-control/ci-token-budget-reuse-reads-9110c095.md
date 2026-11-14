---
bump: patch
---

### Changed

- The babysit merge gate and post-merge check take main's tip from `MAIN_TIP_SHA` when a workflow step already resolved it for the run's own repository, instead of reading `git/ref/heads/main` again: for `_GreenMain.main_tip`, the approval and decision carries, and the post-merge check's branch tip. Without it they read the ref as before.
