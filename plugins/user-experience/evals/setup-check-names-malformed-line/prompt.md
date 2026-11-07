---
description: 'Legacy setup 2. check reports a team file whose routing.disable entry is a flow mapping as FAIL with detect''s skipped reason and line 5, gives the block-mapping rewrite as the remediation, and edits nothing (setup SKILL.md 46-53). fail-row-line-5 and remediation-block grade the reply, file-unchanged the team file; legacy-setup-2 (llm) quotes the three legacy expectations. Needs --scaffold --allow-tools Bash Write Edit.'
tags: [setup, scaffold, no-network, legacy]
runs: 3
expected_outcome: 'The team-file row FAIL naming line 5 (flow mapping outside the subset), a remediation showing the entry as `- job: synthesis` / `id: dovetail` in block style, and the team file left unchanged.'
max_turns: 25
timeout_seconds: 600
allowed_tools: [Bash, Read, Glob, Grep, Write, Edit]
---

/user-experience:setup check

Our docs/conventions/user-experience.yaml has `- {job: synthesis, id: dovetail}` under routing.disable.
