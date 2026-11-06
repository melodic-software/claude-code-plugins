---
description: "Boundary on a bare invocation, SKILL.md lines 76-104: settings.json, .mcp.json, hooks and permissions drift belongs to /harness-config:audit (line 99), so the request is reported as uncovered and that lane is named as the operator's next step, never invoked (lines 86-89). Lines 87-88 now say to name the lane whether or not its plugin is installed and never assert an absent one is available; that replaces the legacy 'when not installed, say it is out of scope instead of routing' line, so the case grades the name, the uncovered statement and no availability claim (only this plugin loads in an eval run). names-owner-lane requires the exact /harness-config:audit name; reports-uncovered the out-of-scope statement; no-available-claim that harness-config is never called installed or available; no-harness-run that no harness-config skill runs; no-settings-fanout that no discovery Agent prompt names settings.json or .mcp.json; no-settings-edit and no-settings-write that neither file changes. Needs --scaffold --allow-tools Write Edit."
tags: [codebase-health, audit, outcome, boundary, no-network]
max_turns: 40
timeout_seconds: 1200
allowed_tools: [Skill, Read, Glob, Grep, Agent, Write, Edit]
expected_outcome: "The reply says settings.json and .mcp.json schema and hook or permission checks are out of this skill's scope and names /harness-config:audit as the lane to run, without claiming it is installed. No harness-config skill runs, no Agent prompt names settings.json or .mcp.json, and neither file is written or edited."
---

/codebase-health:audit

Check my .claude/settings.json and .mcp.json for schema drift, and tell me whether my hooks and permissions are misconfigured.
