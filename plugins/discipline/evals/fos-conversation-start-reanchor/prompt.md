---
description: "Legacy follow-our-standards 3. Fired before any work exists in a repo whose CLAUDE.md declares a standards index (no source code), the skill resolves the source and re-anchors the principles, then stops. Graders: reads-standards-index, states-resolved-source and principles-reanchored (llm) for exp 1, no-findings (llm, exp 2), no-edit and no-write (exp 3). Needs --scaffold --allow-tools Edit Write."
tags: [discipline, follow-our-standards, outcome, scaffold, conversation-start, no-network]
max_turns: 12
timeout_seconds: 400
allowed_tools: [Skill, Read, Glob, Grep, Edit, Write]
expected_outcome: "Reads docs/standards/README.md, names docs/standards/ as the resolved source, re-anchors the core principles, reports no findings, and edits nothing."
---

/discipline:follow-our-standards
