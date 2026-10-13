---
description: "Given an attribution record, the audit's per-tool report carries the binary stamp, keeps prefix and deferred apart, reports the incomparable row by reason without numbers, and prices a basket per bucket"
tags: [context-budget, audit, outcome, report-contract]
runs: 3
max_turns: 15
timeout_seconds: 600
allowed_tools: [Skill, Read, Glob, Grep]
expected_outcome: "The reply states the stamp (path, 2.1.297, sdk/exact, headless); lists prefixDelta and deferredDelta separately for WebFetch, NotebookEdit and TodoWrite; reports Workflow as incomparable with the skill-listing reason and none of its numbers; gives the deferred basket saving as the sum 3,742 and calls the prefix sum 2,922 only an upper bound."
---

/context-budget:audit Here is the attribution record from the run I did on this machine this morning. Write the per-tool section of the report from it, and tell me what denying WebFetch, NotebookEdit and TodoWrite together would save.

```json
{
  "schema": "context-budget.attribution/1",
  "binary": { "path": "/usr/local/lib/claude-code/bin/claude", "version": "2.1.297" },
  "mode": "sdk",
  "precision": "exact",
  "sessionKind": "headless",
  "model": "claude-sonnet-5-5",
  "baseline": { "totalTokens": 38152, "maxTokens": 200000 },
  "perTool": [
    { "tool": "WebFetch", "prefixDelta": -1387, "deferredDelta": -2264, "savedTokens": 3651, "comparable": true, "reasons": [] },
    { "tool": "NotebookEdit", "prefixDelta": -913, "deferredDelta": -1478, "savedTokens": 2391, "comparable": true, "reasons": [] },
    { "tool": "TodoWrite", "prefixDelta": -622, "deferredDelta": 0, "savedTokens": 622, "comparable": true, "reasons": [] },
    { "tool": "Workflow", "prefixDelta": -4471, "deferredDelta": -529, "savedTokens": 5000, "comparable": false,
      "reasons": ["skill-listing signature changed between the baseline and the deny run"] }
  ],
  "knownUncovered": { "tools": [], "notes": [], "deniedAbsent": [] },
  "caveats": []
}
```
