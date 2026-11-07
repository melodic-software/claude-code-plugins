---
description: "Legacy do-your-research 11 (prompt verbatim, its dash a colon). The chained history summarizes the gateway's deployment config, version pins and rollout plan in nine claims, four wrong (replicas, maxUnavailable, the requests pin, the abort threshold); the shared fixture seeds the files. Graders: skill-fired (with-only), no-skill-handoff and agent-dispatched (exp 1), typed-inventory (exp 2), ledger-sources-verdicts (llm, exp 3), states-depth-and-source (exp 4), no-mutating-gh-api (exp 5; parent trace only). A history_file case runs single-arm on a path target. Needs --scaffold --allow-tools Bash."
tags: [discipline, do-your-research, outcome, fan-out, scaffold, history, no-network]
max_turns: 60
timeout_seconds: 1800
allowed_tools: [Skill, Read, Glob, Grep, Bash, Agent]
expected_outcome: "Routes the request to the fan-out tier, lists the nine claims typed, verifies them against the gateway files, corrects four, reports a per-item ledger, and states the resolved depth and where it came from."
---

Go make sure those are all right: fact-check everything we've established about the deployment config, the version pins, and the rollout plan. (This work is read-only: any `gh api` call must be a GET, so pass `--method GET` (or `-X GET`) whenever you add `-f` query fields.)
