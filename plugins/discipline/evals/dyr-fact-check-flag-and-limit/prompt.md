---
description: "Legacy do-your-research 5 (prompt verbatim plus one line naming the tool, since no network: the scaffold's synccli source and docs/limits.md are the live environment). The flag is --jobs (no --parallel) and the free tier allows 1,000 requests a day. Graders: skill-fired (with-only; 'Fact-check that' routes to research discipline, exp 1), located-findings (llm, exp 2), checks-workspace, flag-corrected and limit-corrected (exp 3), stays-inline (no read of reference/fan-out-tier.md, both arms) and stays-inline-reply (llm) for exp 4. Needs --scaffold; read-only tools."
tags: [discipline, do-your-research, outcome, scaffold, no-network]
max_turns: 20
timeout_seconds: 600
allowed_tools: [Skill, Read, Glob, Grep]
expected_outcome: "Checks synccli's source and docs, and corrects both claims: the flag is --jobs and the free tier allows 1,000 requests a day; stays in the inline audit."
---

You said the CLI flag is --parallel and the free tier allows 100 requests a day. Fact-check that. (Both are about this repository's synccli tool.)
