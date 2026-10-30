---
description: "The repository's convention home sets diagram_dialect.data to dbml: the data-scope design writes entity-relationships.md labeled dialect dbml with a dbml fenced block, resolved through the plugin's authoring-formats ladder"
tags: [design, conventions, dialect, data, scaffold]
runs: 3
max_turns: 30
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write, Edit]
expected_outcome: "The design resolves diagram_dialect.data to dbml from docs/conventions/authoring-formats/README.md and writes .work/library-loans/design/entity-relationships.md whose frontmatter says dialect: dbml and whose diagram is a dbml fenced block, not a mermaid erDiagram"
---

/planning:design data

Topic slug `library-loans`; the Brief is in `.work/library-loans/PLAN.md`. Write the entity-relationships artifact for the model the Brief describes, then stop for my answers on anything open. Don't write any code.
