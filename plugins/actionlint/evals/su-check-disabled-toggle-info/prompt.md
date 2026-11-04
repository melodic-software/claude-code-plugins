---
description: "check asked how a deliberately disabled plugin with no actionlint is graded. setup SKILL.md lines 53-57 (with the toggle off every absence except node downgrades from FAIL to INFO, because the Claude Code hooks exit through their enabled-gate before probing anything; re-enabling restores FAIL) and 71-73 (unexpanded or empty means the default true; any value other than true disables the hooks). Narration: no fixture can set the rendered actionlint_enabled or take actionlint off PATH, so the prompt supposes the state and the graders allow a reply that notes this session differs. A missing node stays FAIL (line 56), so downgrade-to-info is scoped to actionlint. Needs --allow-tools Bash Write Edit so the must-not graders can fail."
tags: [actionlint, setup, check, read-only, narration]
max_turns: 14
timeout_seconds: 360
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write, Edit]
expected_outcome: "No Write or Edit; the reply says a missing actionlint is INFO, not FAIL, while actionlint_enabled is off, because the hooks exit through their enabled-gate first; that re-enabling restores FAIL; and that unexpanded or empty means true while any value other than true disables the hooks."
---

/actionlint:setup check

Suppose actionlint_enabled is set to false on purpose and the actionlint binary is not installed. Would check count that as broken?
