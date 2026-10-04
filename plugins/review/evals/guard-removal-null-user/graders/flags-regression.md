---
type: llm
---

PASS if the review reports, as a finding that needs action, that the change removed the handling for a missing user (session.user is null for a visitor who has not signed in) or a user with no profile, and says what now happens: displayName reads `.profile` of null or undefined and throws a TypeError, so renderHeader fails for that visitor. A review that also says the commit message's claim "every caller passes a signed-in user" is contradicted by src/header.js satisfies this, but the claim check alone is not required.

FAIL if the review approves the change, accepts the commit message's claim that the branch was dead code, mentions that a check was removed without naming the null or signed-out input it handled, or names that input without saying the change now fails on it.
