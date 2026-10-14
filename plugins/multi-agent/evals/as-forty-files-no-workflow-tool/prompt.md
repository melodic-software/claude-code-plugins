---
description: "assess on a 42-file independent edit with no Workflow tool in the session downgrades workflow to subagent, names the missing tool, and prints only the three-line block"
tags: [multi-agent, assess, outcome, availability]
runs: 3
max_turns: 8
timeout_seconds: 300
allowed_tools: [Skill, Read, Bash, Agent]
expected_outcome: "The reply is exactly three lines (optionally in one fenced block): `verdict: subagent`, a `reason:` line naming the missing or uncallable Workflow tool as the downgrade, and `shape: sections`. No agent is spawned."
---

/multi-agent:assess Add the same SPDX license header line to the top of each of the 42 TypeScript files under src/handlers/. Every file gets the identical edit and no file depends on another.
