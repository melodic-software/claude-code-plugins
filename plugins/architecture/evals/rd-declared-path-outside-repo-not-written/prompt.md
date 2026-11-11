---
description: "A repository whose AGENTS.md declares an ADR directory outside the repository records the decision in its own docs/adr as 0003, and never writes, creates or offers the outside path"
tags: [architecture, record-decision, outcome, scaffold]
max_turns: 25
timeout_seconds: 600
allowed_tools: [Skill, Bash, Read, Glob, Grep, Write, Edit]
expected_outcome: "The run writes one new record, docs/adr/0003-<title>.md, in the current repository, numbered after the two local records. It makes no Write, Edit or shell call that creates or changes anything under platform-docs or ../platform-docs, and does not treat the declared ../platform-docs/docs/adr line as the place to record the decision."
---

/architecture:record-decision Cache order totals in Redis. Context: the storefront reads order totals on every page view, and the orders table is the bottleneck at peak. We weighed a read replica and rejected it because replica lag showed stale totals after checkout. Consequences: totals must be invalidated on every order change, and removing the cache later means sizing the primary store for peak reads again.
