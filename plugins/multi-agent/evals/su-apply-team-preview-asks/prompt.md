---
description: "Legacy setup 2, first turn. Scaffold: a git repository with no multi-agent layer. setup SKILL.md apply steps 1-5 (lines 51-77): check shows the before map, the team layer fits a whole-repository setting, the preview runs setup.sh apply --layer team roles.verifier.effort=xhigh without --write and prints docs/conventions/multi-agent.yaml with a diff (run locally against this fixture), and the reply asks for an explicit yes. names-target-path needs a write or create verb (setup.sh prints would write:) before that path on one line, since the before map's team layers row names the path too. The write on yes, the after check and the git offer need a second user turn and are held. Order between the two Bash calls is not graded: tool_order cannot tell two Bash calls apart. team-file-absent proves the gate held, since a --write there would succeed and keep the run VALID. Write and Edit are granted so the must-not graders can fail. ran-check and preview-team-ran are with-only indicators. Needs --scaffold --allow-tools Bash Write Edit."
tags: [multi-agent, setup, outcome, write-posture, no-network]
runs: 3
max_turns: 10
timeout_seconds: 300
allowed_tools: [Skill, Read, Bash, Write, Edit]
expected_outcome: "setup.sh check runs and the before map is shown; setup.sh apply --layer team roles.verifier.effort=xhigh runs as a preview only; the reply names docs/conventions/multi-agent.yaml, shows the + effort: xhigh diff line and asks for a yes. No --write, no Write, Edit or shell write of a layer, no git add or commit, and the team file does not exist."
---

/multi-agent:setup apply. I want the verifier role at xhigh effort for everyone on this repo.
