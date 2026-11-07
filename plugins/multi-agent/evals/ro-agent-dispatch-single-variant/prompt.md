---
description: "Legacy route 6, natural language with session=fable stated literally. route SKILL.md lines 67-71: an Agent dispatch with no named type applies the single-agent variant: omit model when omit_model is true, else pass its model, and always pass its effort. Under Fable the worker's single variant is inherit (omit_model true) @ medium, its fan-out opus (run locally). says-omit-model and passes-effort-medium need words the prompt lacks and skip the per-role lines, whose inherit: omit the model option wording is the resolver's; passes-effort-medium also skips the JSON's \"effort\" key. no-model-on-call fails a model value of fable or inherit anywhere; no-model-in-agent-snippet fails an Agent( snippet that carries any model key, so passing the fan-out variant's opus on the call fails while a prose mention of it passes. invoked-route and ran-route-worker-fable are with-only indicators. Needs --allow-tools Bash."
tags: [multi-agent, route, outcome, agent-dispatch, no-network]
runs: 3
max_turns: 8
timeout_seconds: 300
allowed_tools: [Skill, Read, Bash]
expected_outcome: "route.sh worker session=fable runs; the reply says to omit model on the Agent call (the single variant's omit_model is true) and to pass effort medium, and never sets model to fable or inherit."
---

I'm spawning one worker subagent through the Agent tool, no named agent type. This session runs on Fable (session=fable). What do I put on the Agent call?
