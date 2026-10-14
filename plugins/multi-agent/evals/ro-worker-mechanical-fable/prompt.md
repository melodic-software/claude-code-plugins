---
description: "route worker mechanical under a Fable session prints the fenced JSON, the per-role line with sonnet for both variants, and the verbatim hard-cap line"
tags: [multi-agent, route, outcome]
runs: 3
max_turns: 8
timeout_seconds: 300
allowed_tools: [Skill, Read, Bash]
expected_outcome: "route.sh runs; the reply holds its JSON in one fenced json block, the line `worker: single sonnet @ medium; fanout sonnet @ medium (basis: model upstream, fanout model upstream, effort upstream)`, and the verbatim line `Effort above maxEffortLevel runs at the cap; see reference/config.md \"Hard cap\".`"
---

/multi-agent:route worker mechanical session=fable
