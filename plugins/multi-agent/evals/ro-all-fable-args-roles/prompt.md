---
description: "Legacy route 1, natural language with the alias stated literally (session=fable), since the eval model is not Fable. route SKILL.md lines 24-28 and 39-49: route.sh all with session=fable, the JSON unchanged in one fenced json block, one line per role with inherit written as inherit: omit the model option. Under Fable the fan-out guard sends orchestrator, worker and verifier fan-out variants to opus (setup SKILL.md lines 87-91). Line graders check the model and effort, not the basis, which changes with defaults.yaml. invoked-route and ran-route-all-fable are with-only indicators. Needs --allow-tools Bash."
tags: [multi-agent, route, outcome, fanout-guard, no-network]
runs: 3
max_turns: 8
timeout_seconds: 300
allowed_tools: [Skill, Read, Bash]
expected_outcome: "route.sh all session=fable runs; the reply holds its JSON in one fenced json block (worker fan-out model opus), then per-role lines where orchestrator, worker and verifier read single inherit: omit the model option and fanout opus, and no variant reads a bare inherit."
---

Give me the role map to pass as args.roles to a workflow. This session runs on Fable (session=fable).
