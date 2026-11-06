---
description: 'Narration: the baseline snapshot record is given as data because the eval sandbox cannot spawn the headless measurement session. audit SKILL.md lines 56-62: only measured numbers, every report stamped with binary path and version, mode and session kind; lines 228-229: attribution candidates come from the record''s live tools list, never a memorized inventory; lines 359-360: a bare audit changes no configuration. stamp-carried and categories-reported grade the stamp and the measured totals; candidates-from-live-list needs LSP and Monitor (in the record''s tools); no-absent-candidate fails a reply that offers WebFetch, WebSearch, TodoWrite or NotebookEdit, which the record''s tools list leaves out, unless the same sentence says it is not in the list; no-per-tool-figure fails a per-tool token figure, which a baseline record does not hold; figures-from-record (llm) fails any other token figure; no-edit and no-write guard against a configuration write.'
tags: [context-budget, audit, outcome, report-contract, measured-only, narration, no-network]
runs: 3
max_turns: 15
timeout_seconds: 600
allowed_tools: [Skill, Read, Glob, Grep]
expected_outcome: 'The reply stamps the report with /opt/claude/bin/claude, 2.1.304, sdk/exact and headless; reports the measured category totals from the record (9,874 System tools, 6,412 deferred); offers attribution candidates only from the record''s tools list (LSP and Monitor among them, never WebFetch, WebSearch, TodoWrite or NotebookEdit); states no per-tool or other token figure the record does not hold; edits and writes no file.'
---

/context-budget:audit This is the baseline snapshot my audit took on this machine this morning; I have not run attribution yet. Write the report's stamp and category totals from it, and tell me which tools I could attribute next.

```json
{
  "schema": "context-budget.snapshot/1",
  "mode": "sdk",
  "precision": "exact",
  "sessionKind": "headless",
  "binary": { "path": "/opt/claude/bin/claude", "version": "2.1.304" },
  "sdk": { "version": "0.9.12", "entry": "sdk/node_modules/@anthropic-ai/claude-agent-sdk/sdk.mjs" },
  "model": "claude-sonnet-5-5",
  "deny": [],
  "categories": {
    "System prompt": 3120,
    "System tools": 9874,
    "System tools (deferred)": 6412,
    "Memory files": 1205,
    "Skills": 2840,
    "Messages": 12
  },
  "totalTokens": 17051,
  "maxTokens": 200000,
  "tools": ["Agent", "Bash", "Edit", "Glob", "Grep", "LSP", "Monitor", "Read", "Skill", "ToolSearch", "Write"],
  "skillListing": { "totalSkills": 41, "includedSkills": 41, "collapsedSkills": 0, "tokens": 2840, "signature": "9f3c2a7d" },
  "caveats": []
}
```
