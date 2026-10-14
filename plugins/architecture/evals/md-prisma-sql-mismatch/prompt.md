---
description: "A Prisma schema (User has many Posts) and a SQL migration that makes Post.authorId UNIQUE disagree: the ERD stays on the Prisma tier as one-to-many and the cardinality disagreement is recorded and reported as a mismatch, not silently resolved"
tags: [architecture, map-data, outcome, scaffold]
max_turns: 25
timeout_seconds: 600
allowed_tools: [Skill, Bash, Read, Glob, Grep, Write, Edit]
expected_outcome: "data-model.json is drawn from the prisma tier with the Post to User relationship as ||--o{ and one cardinality mismatch naming ||--o{ in prisma and ||--o| in sql-migration; data-model.md draws User ||--o{ Post and no one-to-one marker; the final reply reports one mismatch."
---

/architecture:map-data --out docs/architecture
