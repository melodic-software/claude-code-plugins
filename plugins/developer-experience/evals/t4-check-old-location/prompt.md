---
description: "Scenario T4, turn 1: setup check on the legacy tarnquill copy, whose conventions file sits in .claude/ and holds a false `--yes` line, and whose CLAUDE.md has no @AGENTS.md import. A plugin-arm pass/fail case: the no-plugin arm gets a slash command it cannot run. Turn 2 (apply) is not here, since a case sends one user turn"
tags: [setup, pass-fail]
max_turns: 30
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Write, Edit, Bash, Skill]
expected_outcome: "Nothing is written: AGENTS.md, CLAUDE.md and the .claude/ file stay as seeded. The report names .claude/developer-experience.md as an old location to migrate from, reports the `tq commit` accepts `--yes` line as false, says CLAUDE.md lacks the AGENTS.md import and prints @AGENTS.md alone on a line to add"
---

/developer-experience:setup check
