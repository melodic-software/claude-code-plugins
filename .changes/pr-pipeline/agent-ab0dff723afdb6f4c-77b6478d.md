---
bump: patch
---

### Fixed

- pr-merge's enable-auto-merge job no longer fails its arm with `fetch failed` after a long verifier read. Every request now sends `Connection: close`, so none goes out on a pooled keep-alive connection that sat idle while the verifier ran and that GitHub had closed. A GraphQL request that still fails on the network (Node's "fetch failed", or a cause code of `ECONNRESET`, `ETIMEDOUT`, `UND_ERR_SOCKET` or `UND_ERR_CONNECT_TIMEOUT`, or "other side closed") is sent up to twice more, after full-jitter waits capped at 4 s and then 8 s. An HTTP error answer or a GraphQL error is not sent again. A resent arm passes the same `expectedHeadOid`, so it arms only the head the run read. A pull request whose arm or disarm still fails is left as it was and named with the error's cause code and message, with any token scrubbed. The run then goes on to the other pull requests and exits 1.
