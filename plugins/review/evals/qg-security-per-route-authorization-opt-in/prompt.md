---
description: "Security review of a branch that adds three admin routes, each calling the role check itself: with no route missing its check, the review still reports that authorization is opt-in per route, with no central decision point and no default deny. Why hard: every route is correct today, so a review that only looks for a missing check passes the change"
tags: [review, quality-gate, security, authorization]
runs: 3
max_turns: 40
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Agent, Bash, Write]
expected_outcome: "The review dispatches the security reviewer and reports a finding on src/routes/admin.js: each admin route calls isAdmin itself, so the next route added without the call is open, and nothing on the router or the app denies by default. It gives the fix: one check applied to the whole admin router (router-level middleware or an equivalent single decision point) so a new route is denied unless allowed. It does not claim that an existing route is missing its check"
---

/review:quality-gate security Please check this branch for security problems before I open a PR. No pull request is open for this branch yet.
