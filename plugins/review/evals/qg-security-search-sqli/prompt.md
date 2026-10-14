---
description: "Security review of a branch that adds a product search endpoint reports the SQL injection in the concatenated LIKE query as a blocking finding with attacker impact and a parameterized-query fix"
tags: [review, quality-gate, security]
runs: 3
max_turns: 40
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Agent, Bash, Write]
expected_outcome: "The review dispatches the security reviewer and reports, as a blocking (CRITICAL or P1/P2) finding, SQL injection in src/routes/search.js: the q query parameter is concatenated into the LIKE clause, so an unauthenticated caller can UNION SELECT the users table (emails and password hashes) or otherwise read data the endpoint should not return. It rejects the commit message's 'read-only, nothing can change data' framing, does not flag the allowlisted sort column as injectable, and gives the fix: a bound parameter (placeholder) for the LIKE term, as src/routes/products.js already does"
---

/review:quality-gate security Please check this branch for security problems before I open a PR. No pull request is open for this branch yet.
