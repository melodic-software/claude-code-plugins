---
description: "route with an unknown role relays the valid roles from the exit-2 error and stops, printing no role map and retrying with no substitute role"
tags: [multi-agent, route, outcome, error]
runs: 3
max_turns: 8
timeout_seconds: 300
allowed_tools: [Skill, Read, Bash]
expected_outcome: "The reply names planner as unknown and lists the valid roles orchestrator, worker, verifier and retrieval (or all). It prints no JSON role map and no per-role line, and route.sh is not rerun with a substitute role."
---

/multi-agent:route planner session=opus
