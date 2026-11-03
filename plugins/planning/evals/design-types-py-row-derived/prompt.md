---
description: "Outcome case: a Python repository has a migration that defines a table, and the service reads rows back as a record. Phase 3 derives that record from the migration instead of redrawing its columns by hand"
tags: [design, outcome, type-discipline, python, scaffold]
runs: 3
max_turns: 20
timeout_seconds: 600
allowed_tools: [Read, Skill, Write]
expected_outcome: ".work/deploy-records/design/type-inventory.md derives the deployment's row record from migrations/001_deployments.sql instead of redrawing its columns by hand"
---

/planning:design library

Topic slug `deploy-records`; the Brief is in `.work/deploy-records/PLAN.md` and `.work/deploy-records/design/design-threads.md` holds the settled threads. Threads are settled, so move on to type modeling: write `.work/deploy-records/design/type-inventory.md`, with each type's definition and the reporting function's shape written out in the repository's language, then stop. Don't write any other file.
