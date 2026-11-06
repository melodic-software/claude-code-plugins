---
description: "assess on a 42-file independent edit with no Workflow tool in the session downgrades workflow to subagent, names the missing tool, and prints only the three-line block. Also covers legacy assess 1 (140 skill files, verdict workflow): an eval session offers no Workflow tool, so its workflow verdict cannot be reached and this downgrade is what stays measurable. From it: ran-availability-script (with-only; SKILL.md step 1 runs the script before the verdict), reason-names-item-count (the count on the reason line), and no Workflow, Write or Edit call."
tags: [multi-agent, assess, outcome, availability]
runs: 3
max_turns: 8
timeout_seconds: 300
allowed_tools: [Skill, Read, Bash, Agent]
expected_outcome: "The reply is exactly three lines (optionally in one fenced block): `verdict: subagent`, a `reason:` line naming the missing or uncallable Workflow tool as the downgrade, and `shape: sections`. workflow-availability.sh runs, the reason names the 42 files, and no agent, workflow, Write or Edit call is made."
---

/multi-agent:assess Add the same SPDX license header line to the top of each of the 42 TypeScript files under src/handlers/. Every file gets the identical edit and no file depends on another.
