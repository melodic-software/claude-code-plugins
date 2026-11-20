---
bump: patch
---

### Changed

- Run titles start with the workflow's Title Case name: `PR Merge: arm #<n>`, `PR Rate Merge Risk #<n> <sha>`, `PR Refine <activity> #<n>`, `PR Unblock <activity> #<n>` and `PR Verify Capture <run-id> <sha>`. Every reader still accepts the old lowercase titles, so runs started before this change keep matching.
