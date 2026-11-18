---
description: "CLAUDE.md imports docs/team-rules.md, which does not exist: /discipline:follow-operating-procedures names that file as missing and still reports on CLAUDE.md's own rules. Needs --scaffold --allow-tools Bash."
tags: [follow-operating-procedures, scaffold]
runs: 3
max_turns: 30
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Skill, Bash]
expected_outcome: "Reads CLAUDE.md, names docs/team-rules.md as missing, and still reports that CLAUDE.md's rules govern the work"
---

/discipline:follow-operating-procedures
