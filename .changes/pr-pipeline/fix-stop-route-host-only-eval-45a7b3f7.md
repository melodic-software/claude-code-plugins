---
bump: patch
---

### Fixed

- A work-resolve-issue stop whose code ends the lane's work (close, host-run or attended) and whose reason names a secret only as a capability the run needs, such as "a host with model credentials", "needs an API key" or "tokens per task", now keeps its route instead of holding for a person. Any other mention of a credential, secret, token, password or key after such a code, or one beside an exposure or disclosure word anywhere in the reason (log, summary, shared, rotated, revoked, emailed and the like), still holds as `security-risk`, as do takeover, stolen, attacker, stranger and outsider wording.
