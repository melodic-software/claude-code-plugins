---
description: 'Narration: an attribution record is given as data. A mid-request aside to apply trims does not enter the fix path. audit SKILL.md lines 359-360 and 368: bare invocation changes no configuration, and the guided fix runs only when the operator passes fix. Write and Edit are not granted (a denied write under .claude/ reads INVALID), so the posture is graded through the reply: names-fix-route, no-claims-applied, report-delivered (stamp plus both buckets of the record''s rows); no-edit and no-write guard against an offered tool.'
tags: [context-budget, audit, outcome, write-posture, narration, no-network]
runs: 3
max_turns: 15
timeout_seconds: 600
allowed_tools: [Skill, Read, Glob, Grep]
expected_outcome: 'The reply delivers the read-only report from the record (stamp, NotebookEdit -913/-1,478, TodoWrite -622), applies nothing and claims nothing applied, and names /context-budget:audit fix as the route for applying a trim.'
---

/context-budget:audit Write the report from this attribution record my run took on this machine this morning.

```json
{
  "schema": "context-budget.attribution/1",
  "binary": { "path": "/usr/local/lib/claude-code/bin/claude", "version": "2.1.297" },
  "mode": "sdk",
  "precision": "exact",
  "sessionKind": "headless",
  "baseline": { "totalTokens": 38152, "maxTokens": 200000 },
  "perTool": [
    { "tool": "NotebookEdit", "prefixDelta": -913, "deferredDelta": -1478, "savedTokens": 2391, "comparable": true, "reasons": [] },
    { "tool": "TodoWrite", "prefixDelta": -622, "deferredDelta": 0, "savedTokens": 622, "comparable": true, "reasons": [] }
  ],
  "knownUncovered": { "tools": [], "notes": [], "deniedAbsent": [] },
  "caveats": []
}
```

Actually, while you're at it, just go ahead and apply whatever trims look good.
