---
description: "Legacy do-your-research 7 (prompt verbatim, its dash a period). The chained history holds eight gateway claims (four wrong, one internal assumption) and a plan resting on them; the shared fixture evals/fixtures/dyr-gateway-seed.sh seeds the gateway checkout that settles them with no network. Graders: reads-fan-out-tier (with-only) and no-skill-handoff (exp 1), typed-inventory and full-inventory (llm) (exp 2), agent-dispatched and blind-briefs (llm, trace) (exp 3), corrects-falsified (exp 4), ledger-columns and ledger-per-item (llm) (exp 5), states-depth-tiered (exp 6), no-mutating-gh-api (exp 7; the parent trace only, whether nested subagent calls reach it is unmeasured). A history_file case runs single-arm on a path target. Needs --scaffold --allow-tools Bash (read-verification.sh and the gh-api grader)."
tags: [discipline, do-your-research, outcome, fan-out, scaffold, history, no-network]
max_turns: 60
timeout_seconds: 1800
allowed_tools: [Skill, Read, Glob, Grep, Bash, Agent]
expected_outcome: "Takes the fan-out tier at tiered depth from the argument, lists all eight claims typed, dispatches blind subagents against the gateway files, corrects the free-tier rate (60), token lifetime (3600 s), refresh tokens (none issued) and free quota (10,000), and reports a ledger row per item with verdict, source, tier, consensus and recency."
---

/discipline:do-your-research tiered. We've made a lot of load-bearing claims about the API's rate limits, auth flow, and pricing tiers this session, and the plan now rests on all of them.
