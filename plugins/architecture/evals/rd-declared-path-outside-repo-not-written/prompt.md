---
description: "A repository whose AGENTS.md declares an ADR directory outside the repository records the decision in its own docs/adr as 0003, and never writes, creates or offers the outside path"
tags: [architecture, adr, outcome, scaffold]
max_turns: 25
timeout_seconds: 600
allowed_tools: [Skill, Bash, Read, Glob, Grep, Write, Edit]
expected_outcome: "The run writes one new record, docs/adr/0003-<title>.md, in the current repository, numbered after the two local records. It makes no Write, Edit or shell call that creates or changes anything under platform-docs or ../platform-docs, and does not treat the declared ../platform-docs/docs/adr line as the place to record the decision."
---

/architecture:adr Add order totals to every order event the billing and analytics services consume. Context: both services recomputed totals from order lines and disagreed with the storefront on rounding. We weighed having them call the orders API for totals and rejected it because the API would sit on their hot path at peak. Consequences: the totals field becomes part of the event contract two other services read, events already published carry it, and removing it later needs a coordinated release of all three services.
