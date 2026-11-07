---
description: "Legacy do-your-research 13 (prompt verbatim). The chained history holds two dozen unverified gateway claims; the shared fixture seeds the gateway. The prompt never says audit-only, so restraint must come from the skill's never-inside-a-batch-or-a-fork guard. Graders: skill-fired (with-only), no-agent (exp 1), cites-fork-guard (llm, exp 2), no-write and no-edit plus findings-ledger (llm) (exp 3), recommends-direct-run (exp 4). A history_file case runs single-arm on a path target. Needs --scaffold --allow-tools Write Edit."
tags: [discipline, do-your-research, outcome, fan-out, fork-guard, scaffold, history, no-network]
max_turns: 30
timeout_seconds: 900
allowed_tools: [Skill, Read, Glob, Grep, Write, Edit, Agent]
expected_outcome: "Stays inline inside the fork, dispatches no subagent, cites the fork guard, returns a findings ledger without writing, and recommends a direct /discipline:do-your-research tiered run."
---

You are a fork dispatched by /discipline:sweep-all for the research pass. Load /discipline:do-your-research and work through this session's claims, make no writes, and return what you find. (The session has dozens of unverified load-bearing claims, the user said earlier to fact-check everything, and your Agent tool is available and able to spawn subagents.)
