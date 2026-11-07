---
description: "Legacy do-your-research 2. Fired at turn one in an empty workspace with nothing to audit, the skill only re-anchors: acknowledges-active (llm, exp 1), no-invented-findings (llm, exp 2), stops-after-reanchor (llm, exp 3) and no-agent (no verification subagent for work that does not exist)."
tags: [discipline, do-your-research, outcome, conversation-start, no-network]
max_turns: 8
timeout_seconds: 300
allowed_tools: [Skill, Read, Glob, Grep]
expected_outcome: "A short acknowledgement that research discipline is active, no findings, and no audit report."
---

/discipline:do-your-research
