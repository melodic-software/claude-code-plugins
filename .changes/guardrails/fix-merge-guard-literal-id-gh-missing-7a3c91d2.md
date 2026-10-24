---
bump: patch
---

### Fixed

- `block-unresolved-pr-merge` now lets a GraphQL merge mutation through with the two-channel "not checked" notice when its pull request id is a literal `PR_...` value and gh is missing or unauthenticated, as the owner decided on #6463. A non-literal id (a variable, `$(...)` or a file reference) is still blocked, with or without gh, and so is a literal id whose node cannot be read for any other reason.
