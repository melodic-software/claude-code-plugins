---
description: "Routine. The effort-pins scope runs only the effort-pin drift check: SKILL.md Arguments, '`effort-pins`: run only the effort-pin drift check (Phase 3) and report its lines verbatim; no engine run and no fixes'; Phase 3 names the call, scripts/check-effort-pins.sh --docs-dir <dir>. Offline the check may exit 3 (page unread), which still counts as running it. Source: the before SKILL.md contract. Needs --scaffold --allow-tools Bash Write Edit."
tags: [routine, audit, outcome, scope, scaffold]
runs: 3
max_turns: 15
timeout_seconds: 900
allowed_tools: [Skill, Read, Glob, Grep, Bash, Write, Edit]
expected_outcome: "check-effort-pins.sh runs; audit-engine.sh and fix-plugin-drift.sh never run; no Write or Edit touches a settings file."
---

/harness-config:audit effort-pins
