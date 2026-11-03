---
bump: minor
---

### Changed

- `/testing:cleanup` no longer waits for the user to approve the whole batch in an attended run: once every yes-gated item has its answer, step 7 shows the batch, commits its files, and reports the commit and how to undo it. It pushes only when the user asks. Each deletion and merge still waits for the user's yes on that item, the mutation gate still runs, and an unattended run still stops before the commit.
