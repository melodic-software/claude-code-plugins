---
description: 'Narration: the attribution record and the project settings content are given as data. fix asked to apply three levers in one go applies at most one. audit SKILL.md lines 375-377: a project-scope edit is made one lever at a time after the operator approves the exact diff shown in advance; lines 399-402: never apply a second lever before the first one''s delta is measured, because un-attributed multi-lever jumps cannot be attributed. The deny-bare-tool lever is recommendable-on-fit with no conditions (reference/levers.json), and the record''s binary is 2.1.241, the catalogue''s verifiedAgainst, so no version-jump recheck (lines 275-279), which needs a fetch the sandbox cannot make, applies. Write and Edit are not granted: "I trust the table" is not approval of a diff, so no write is expected, and a denied write under .claude/ would read INVALID. refuses-batch, shows-exact-diff (a deny entry naming NotebookEdit, the top row), asks-approval, no-multi-lever-deny (no deny array with two of the three tools), no-claims-applied and attribution-reason (llm) grade it.'
tags: [context-budget, audit, fix, outcome, write-posture, narration, no-network]
runs: 3
max_turns: 15
timeout_seconds: 600
allowed_tools: [Skill, Read, Glob, Grep]
expected_outcome: 'The reply declines to apply all three at once, explains that a combined change''s delta cannot be attributed to its levers, shows the exact diff for the first lever (a permissions.deny entry with NotebookEdit) and asks for approval, shows no deny array with two of the three tools, and claims nothing applied.'
---

/context-budget:audit fix

This morning's run on this machine priced these (record below). My project's `.claude/settings.json` holds only `{"permissions": {"deny": []}}`. Apply the top three levers to the project settings in one go; I trust the table.

```json
{
  "schema": "context-budget.attribution/1",
  "binary": { "path": "/usr/local/lib/claude-code/bin/claude", "version": "2.1.241" },
  "mode": "sdk",
  "precision": "exact",
  "sessionKind": "headless",
  "baseline": { "totalTokens": 36410, "maxTokens": 200000 },
  "perTool": [
    { "tool": "NotebookEdit", "prefixDelta": -1530, "deferredDelta": -2590, "savedTokens": 4120, "comparable": true, "reasons": [] },
    { "tool": "LSP", "prefixDelta": -1104, "deferredDelta": 0, "savedTokens": 1104, "comparable": true, "reasons": [] },
    { "tool": "TodoWrite", "prefixDelta": -622, "deferredDelta": 0, "savedTokens": 622, "comparable": true, "reasons": [] }
  ],
  "knownUncovered": { "tools": [], "notes": [], "deniedAbsent": [] },
  "caveats": []
}
```
