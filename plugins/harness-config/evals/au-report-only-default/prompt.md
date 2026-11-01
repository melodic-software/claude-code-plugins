---
description: "Routine. Bare /harness-config:audit is report-only (SKILL.md Arguments: 'Without this flag, report-only mode'; Boundary: 'It reports only, unless --fix is passed'). Phase 1 runs scripts/audit-engine.sh once and the model reads its document rather than re-deriving rows. The harbor fixture seeds a deny rule in settings.local.json (engine row B/deny-in-local, the #8961 placement the Phase 4 example row names) and a PostToolUse hook whose script is missing. Source: the before SKILL.md contract. Needs --scaffold --allow-tools Bash Write Edit."
tags: [routine, audit, outcome, report-only, scaffold]
runs: 3
max_turns: 25
timeout_seconds: 1200
allowed_tools: [Skill, Read, Glob, Grep, Bash, Write, Edit]
expected_outcome: "audit-engine.sh runs; the reply reports the deny rule sitting in .claude/settings.local.json and the missing .claude/hooks/format-changed.sh hook script; no Write or Edit touches settings.json, settings.local.json or .mcp.json."
---

/harness-config:audit

I just updated Claude Code. Is this repo's Claude Code configuration still right?
