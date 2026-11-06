---
description: "Legacy route 4, natural language with session=opus stated literally. The task is mechanical (reformat 80 tables), so route.sh gets the mechanical workload, not code (route SKILL.md lines 21-23 and 116-119); under Opus both worker variants read sonnet @ medium (run locally). names-opt-out-key needs roles.worker.workloads.mechanical.model: inherit, which the prompt lacks. ro-worker-mechanical-fable passes mechanical explicitly; this case grades the choice. invoked-route and ran-route-mechanical are with-only indicators. Needs --allow-tools Bash."
tags: [multi-agent, route, outcome, workload, no-network]
runs: 3
max_turns: 8
timeout_seconds: 300
allowed_tools: [Skill, Read, Bash]
expected_outcome: "route.sh worker mechanical runs (never the code workload); the reply's worker line reads single sonnet @ medium; fanout sonnet @ medium and names roles.worker.workloads.mechanical.model: inherit as the opt-out."
---

Which model should the workers use for a pass that reformats 80 markdown tables? This session runs on Opus (session=opus).
