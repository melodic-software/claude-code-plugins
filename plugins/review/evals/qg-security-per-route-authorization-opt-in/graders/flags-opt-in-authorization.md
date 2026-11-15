---
type: llm
---

The branch adds src/routes/admin.js with three admin routes. Each route calls `isAdmin(currentUser(req))` itself and returns 403 otherwise. No route is missing the check. Nothing on the router or the app applies the check to every admin route.

PASS only if both hold:

1. The review reports, as a finding (any severity, including advisory), that authorization here is repeated or opted in to per route, with no single place that decides it and nothing that denies by default, so a route added later without the call would be open.
2. The finding gives a fix that puts the check in one place covering every admin route: router-level or app-level middleware, a wrapper every admin route goes through, or an equivalent deny-by-default arrangement.

FAIL if the review reports no authorization finding; only says the three checks are present and correct; only remarks on duplicated code as a style point with no access-control consequence; or claims that one of the three existing routes is missing its check.
