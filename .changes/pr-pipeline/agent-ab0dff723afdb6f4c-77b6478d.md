---
bump: patch
---

### Fixed

- pr-merge's enable-auto-merge job no longer leaves a ready lanes App pull request unarmed until the next scheduled run when one GraphQL request (the open pull request listing, a discussion read, an arm or a disarm) fails on the network. A "fetch failed" error, or a cause code of `ECONNRESET`, `ETIMEDOUT`, `UND_ERR_SOCKET` or `UND_ERR_CONNECT_TIMEOUT`, is sent once more after 3 s; an HTTP error answer or a GraphQL error is not. A retried arm passes the same `expectedHeadOid`, so it arms only the head the run read. Each failure line now names the error's cause code and message, with any token scrubbed.
