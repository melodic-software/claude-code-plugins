---
description: "Legacy do-your-research 9 (prompt verbatim, its dash dropped: a colon glued to the command name stops it expanding). The chained history is one question and one answer citing RFC 6585. Graders: no-fan-out-tier-read (exp 2, both arms), no-agent (exp 4), cost-not-justified (llm, exp 1) and no-big-pass (llm, exp 3). Watch: the shared method's step 2 sends a clean self-audit of load-bearing work to a fresh-context subagent; the legacy case forbids any Agent call here, kept as written. A history_file case runs single-arm on a path target."
tags: [discipline, do-your-research, outcome, history, no-network]
max_turns: 10
timeout_seconds: 400
allowed_tools: [Skill, Read, Glob, Grep, Agent]
expected_outcome: "Recognizes one sourced claim does not justify a fan-out, audits inline, and dispatches no subagent."
---

/discipline:do-your-research verify every claim. (I just asked you one question and you gave one answer citing an official doc.)
