---
description: "setup apply that turns fanout.frontier_guard off previews without writing, states the frontier fan-out consequence, and asks for that key's confirmation separately"
tags: [multi-agent, setup, outcome, write-posture]
runs: 3
max_turns: 10
timeout_seconds: 300
allowed_tools: [Skill, Read, Bash, Write, Edit]
expected_outcome: "setup.sh apply runs as a preview only (no --write), no Write, Edit or shell redirect touches a multi-agent.yaml, and the reply says fan-out stages would then run on the frontier session model and asks the user to confirm the frontier_guard key separately."
---

/multi-agent:setup apply --layer user fanout.frontier_guard=false roles.worker.effort=high
