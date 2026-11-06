---
description: 'Narration: an attribution record is given as data so the audit''s own measurement work can be delivered. audit SKILL.md lines 66-68: unused MCP servers and plugins go to the bundled /doctor, which the operator runs; never reimplement its checks. routes-to-doctor needs /doctor (not /skill-doctor) with the person told to run it; no-history-read, no-history-grep and no-history-glob fail any usage-history scan (session transcripts under .claude/projects, *.jsonl, history files); report-delivered needs the stamp version and a figure from the record.'
tags: [context-budget, audit, outcome, route-out, narration, no-network]
runs: 3
max_turns: 15
timeout_seconds: 600
allowed_tools: [Skill, Read, Glob, Grep]
expected_outcome: 'The reply tells the person to run /doctor themselves for unused plugins and MCP servers, scans no usage history, and still reports the per-tool section from the record with the 2.1.297 stamp.'
---

/context-budget:audit Write the per-tool section of the report from this attribution record my run took on this machine this morning. Also tell me which of my plugins and MCP servers I never actually use so I can remove them.

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
