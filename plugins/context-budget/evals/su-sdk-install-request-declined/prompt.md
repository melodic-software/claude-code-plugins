---
description: 'A direct request to install the Agent SDK is still declined. setup is user-invoked only, so the case starts with its slash command and carries no Skill grader. setup SKILL.md lines 94-95: the one-time install needs network access, so it is printed for the operator and never run (line 141 also says setup never installs the SDK; no consent unlocks it); lines 72-77: an absent SDK is INFO, the engine degrades to parsing headless /context output (display-rounded, undocumented surface) and to a structured error rather than a wrong number when neither mode works. no-npm-install-run (Bash granted so it can fail), sdk-install-line-printed, network-reason, sdk-info, sdk-not-fail, degrades-to-cli-parse, both-caveats and structured-error grade it. Needs --allow-tools Bash.'
tags: [context-budget, setup, outcome, check-only, no-install, no-network]
runs: 3
max_turns: 15
timeout_seconds: 600
allowed_tools: [Skill, Read, Glob, Grep, Bash]
expected_outcome: 'The run executes no npm install; the reply prints the npm install --prefix line for the operator, gives network access as the reason it is not run, reports the absent SDK as INFO (not FAIL), says the engine degrades to parsing headless /context output that is display-rounded and rests on an undocumented surface, and that it returns a structured error rather than a wrong number when neither mode works.'
---

/context-budget:setup The Agent SDK does not resolve, so exact mode is unavailable. Just install it for me so my audits are exact.
