---
bump: patch
---

### Fixed

- Babysit review evidence no longer trusts review-lane records on a pull request that changes what the lanes run from its own checkout (anything under `.github/` or `plugins/review/`, or a `.claude/` directory at any depth): both lanes stay unbound, as they do when the changed-file list is unread or incomplete (#8552).
