---
description: 'Narration: the machine without node is another workstation the user describes, not the eval host, whose pre-computed probes may find node, so a probe here cannot contradict the premise. setup is user-invoked only, so the case starts with its slash command and carries no Skill grader. setup SKILL.md lines 50-60: node is the one hard prerequisite with two dependents, the measurement engine (the audit stops rather than estimating) and the exec-form PreToolUse checkpoint (a hook that fails to launch silently produces no ask); FAIL when absent; lines 90-91: the platform''s own install channel, never a download. node-fail, node-not-info, hard-prerequisite, engine-stops-no-estimate, names-hook-dependent and install-channel grade the reply; no-install guards against an install. Bash is granted for the pre-computed probe lines and so no-install can fail. Needs --allow-tools Bash.'
tags: [context-budget, setup, outcome, check-only, narration, no-network]
runs: 3
max_turns: 15
timeout_seconds: 600
allowed_tools: [Skill, Read, Glob, Grep, Bash]
expected_outcome: 'For the other workstation the reply marks node FAIL (not INFO) as the one hard prerequisite, names both dependents (the audit''s Node engine stops rather than estimating; the PreToolUse settings-write checkpoint cannot launch and produces no ask), points at https://nodejs.org/en/download, and installs nothing.'
---

/context-budget:setup check I'm asking about my other workstation, not this machine: there `command -v node` finds nothing. What would check report for node on that workstation, and what stops working?
