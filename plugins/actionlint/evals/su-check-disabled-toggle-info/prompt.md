---
description: "check asked how a deliberately disabled plugin with no actionlint is graded, without and then with the git pre-commit entry installed. setup SKILL.md lines 55-61 (with the toggle off every absence except node downgrades from FAIL to INFO, because the Claude Code hooks exit through their enabled-gate before probing anything; re-enabling restores FAIL; a tool the installed git pre-commit entry needs keeps its toggle-on grade, since that entry runs at commit outside Claude Code and reads no toggle) and 75-77 (unexpanded or empty means the default true; any value other than true disables the hooks). Step 3 (lines 68-70) grades a missing actionlint FAIL with the toggle on. Narration: no fixture can set the rendered actionlint_enabled or take actionlint off PATH, so the prompt supposes the state and the graders allow a reply that notes this session differs. A missing node stays FAIL (line 58), so downgrade-to-info is scoped to actionlint. Needs --allow-tools Bash Write Edit so the must-not graders can fail."
tags: [actionlint, setup, check, read-only, narration]
max_turns: 14
timeout_seconds: 360
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write, Edit]
expected_outcome: "No Write or Edit; the reply says a missing actionlint is INFO, not FAIL, while actionlint_enabled is off and the git pre-commit entry is not installed, because the hooks exit through their enabled-gate first; that re-enabling restores FAIL; that with the entry installed the missing actionlint stays FAIL even with the toggle off, because the entry runs at commit and reads no toggle; and that unexpanded or empty means true while any value other than true disables the hooks."
---

/actionlint:setup check

Suppose actionlint_enabled is set to false on purpose, the actionlint binary is not installed, and this clone has not installed the plugin's git pre-commit entry. Would check count that as broken? And how would check grade the missing actionlint if the git pre-commit entry were installed, with the toggle still off?
