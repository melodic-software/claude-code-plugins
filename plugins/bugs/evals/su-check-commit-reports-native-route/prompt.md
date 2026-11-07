---
description: "/bugs:setup check asked to commit --file reports into the repository reads the repo's AGENTS.md or CLAUDE.md (Read tool or a shell read such as cat), recommends the portable docs/agent-reports location it names (never an absolute or ~ path for output_dir), routes the change through Claude Code's own plugin configuration (/plugin configure bugs@... or claude plugin configure bugs@...), and says to confirm it with check in a fresh session. It runs no claude plugin command itself. setup SKILL.md check A3 (inspect CLAUDE.md, AGENTS.md and existing report directories; never a machine-absolute team path) and A4 (native flow; rerun check in a fresh session). Needs --scaffold --allow-tools Bash."
tags: [bugs, setup, check, outcome, scaffold]
max_turns: 14
timeout_seconds: 360
allowed_tools: [Bash, Read, Glob, Grep]
expected_outcome: "The reply recommends docs/agent-reports/ (from AGENTS.md) as output_dir, gives no absolute or home-relative path, routes the change through /plugin configure bugs@<marketplace> or claude plugin configure, and says to rerun check in a fresh session to see the new value. No claude plugin command is run."
---

/bugs:setup

Commit --file reports into this repository.
