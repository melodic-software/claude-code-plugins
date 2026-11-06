---
description: "/skill-quality:setup check with skills_root unset and no SKILL.md anywhere must FAIL rather than claim success, and route the fix to Claude Code's own plugin configure flow, never a hand edit of settings. setup SKILL.md: FAIL when the root is absent or empty, never claim success for a missing directory; reconfigure through /plugin configure or claude plugin configure --values-stdin; never write user settings or pluginConfigs. Also carries legacy setup eval 3: no-write, no-edit and no-mkdir grade that setup neither creates .claude/skills nor writes settings for the conventional default. Needs --scaffold."
tags: [skill-quality, setup, check, outcome, read-only, scaffold]
max_turns: 10
timeout_seconds: 240
allowed_tools: [Read, Glob, Grep]
expected_outcome: "The reply reports a FAIL for the missing skills root and points at /plugin configure skill-quality or claude plugin configure skill-quality to set skills_root, without telling the user to edit settings.json or pluginConfigs by hand."
---

/skill-quality:setup check
