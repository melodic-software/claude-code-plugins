---
description: "route with an unknown role relays the valid roles from the exit-2 error and stops, printing no role map and retrying with no substitute role. Also covers legacy route 2 (judge): no-team-layer-file and no-local-layer-file check that no configuration layer was written; Write and Edit are not granted, so the file checks stand in for tool graders whose failure would be a denied write under .claude/ (#13729)."
tags: [multi-agent, route, outcome, error]
runs: 3
max_turns: 8
timeout_seconds: 300
allowed_tools: [Skill, Read, Bash]
expected_outcome: "The reply names planner as unknown and lists the valid roles orchestrator, worker, verifier and retrieval (or all). It prints no JSON role map and no per-role line, and route.sh is not rerun with a substitute role. No layer file exists afterwards."
---

/multi-agent:route planner session=opus
