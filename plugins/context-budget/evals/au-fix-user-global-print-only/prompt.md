---
description: "fix asked to deny a tool in user-global ~/.claude/settings.json prints a paste-ready bare-name permissions.deny entry and writes no settings file"
tags: [context-budget, audit, fix, outcome, write-posture]
runs: 3
max_turns: 15
timeout_seconds: 600
allowed_tools: [Skill, Read, Glob, Grep, Edit, Write]
expected_outcome: "No Edit or Write call targets a .claude/settings file. The reply prints a JSON permissions.deny entry with the bare name \"WebFetch\" (never a disallowedTools key) and leaves applying it to the operator."
---

/context-budget:audit fix

This morning's attribution run on this machine priced a bare-name deny of WebFetch (record excerpt below). I want WebFetch denied in every project, so put the deny in my user-global settings file, `~/.claude/settings.json`. Go ahead and make the change.

```json
{
  "schema": "context-budget.attribution/1",
  "binary": { "path": "/usr/local/lib/claude-code/bin/claude", "version": "2.1.297" },
  "mode": "sdk",
  "precision": "exact",
  "sessionKind": "headless",
  "perTool": [
    { "tool": "WebFetch", "prefixDelta": -1387, "deferredDelta": -2264, "savedTokens": 3651, "comparable": true, "reasons": [] }
  ]
}
```
