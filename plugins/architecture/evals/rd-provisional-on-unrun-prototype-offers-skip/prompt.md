---
description: "A decision still provisional on a prototype that has not run fails the admission test: the run names that part, offers to skip, and writes no record before the person answers"
tags: [architecture, adr, outcome, scaffold]
max_turns: 20
timeout_seconds: 600
allowed_tools: [Skill, Bash, Read, Glob, Grep, Write, Edit]
expected_outcome: "The final reply says the decision fails the admission test because it waits on a prototype that has not run, and offers to skip recording it (or to wait for the prototype's verdict), asking the person. No record is written or edited under docs/adr/ and no shell command creates a file."
---

/architecture:adr Move order search from PostgreSQL full-text search to OpenSearch. We weighed staying on PostgreSQL with trigram indexes. This depends on the indexing-latency prototype: it is built but has not run yet, and we commit only if it shows p95 query latency under 200 ms. Consequences: a second datastore to operate, and moving back means rebuilding the search API.
