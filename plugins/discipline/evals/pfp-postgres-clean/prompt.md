---
description: "Legacy pick-for-the-problem 4. A Postgres choice made from stated requirements after a field survey. reports-clean (regex) and no-churn (llm, legacy expectations 1-3) check that the audit confirms the fit and recommends no switch. Read-only."
tags: [discipline, pick-for-the-problem, outcome, no-network]
max_turns: 12
timeout_seconds: 400
allowed_tools: [Skill, Read, Glob, Grep]
expected_outcome: "Confirms Postgres fits the stated needs and reports clean, without recommending a switch or treating the invocation as an accusation."
---

/discipline:pick-for-the-problem we picked Postgres here because we need transactional integrity and relational queries, and we evaluated the alternatives when we chose it.
