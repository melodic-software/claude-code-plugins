---
description: "check asked how a missing jq and a missing Node.js are graded, with the toggle on and off. setup SKILL.md lines 50-54 (with python_format_enabled off every prerequisite absence except Node.js downgrades from FAIL to INFO, because the hook script exits through its enabled-gate first; Node.js stays FAIL because hooks.json spawns node before the script can read the toggle), step 2 (lines 57-58: a missing jq is FAIL and the batch hook then does nothing, since it reads the file paths with jq) and step 7 (lines 80-82: a missing node is FAIL, a hook launch error, not a skip notice). The legacy 'visible once per session notice' for jq is dropped: the hook exits silently without jq (hooks/python-format.sh line 55), and the session-start probe reports it because prerequisites.json declares jq. Narration: no fixture can take jq or node off the eval host's PATH, so the prompt supposes the state and the graders allow a reply that notes this session differs. Needs --allow-tools Bash Write Edit so the must-not graders can fail."
tags: [python-format, setup, check, read-only, narration, no-network]
max_turns: 14
timeout_seconds: 360
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write, Edit]
expected_outcome: "No install, Write or Edit; the reply grades a missing jq FAIL (the batch hook then does nothing) and a missing Node.js FAIL (a hook launch error, not a skip notice); with python_format_enabled off, the missing jq drops to INFO while Node.js stays FAIL, because node launches the hook before it reads the toggle."
---

/python-format:setup check

Suppose this machine had neither jq nor node on PATH. How would check grade each, what would the hook do without it, and would turning python_format_enabled off change either grade?
