---
description: "Discrimination over three TypeScript tools: get_report has an undescribed reportId (C6 FAIL), no readOnlyHint (C12 WARN, never FAIL) and no when-to-use or returns text (C2/C3); delete_workspace's description leaks Cosmos DB, tombstone and partition-key internals (C5); list_items is a generic CRUD name the checklist accepts, so it must not be flagged under C10; an llm judge checks that the fix guidance puts FAIL first. The skill runs as context: fork; the prompt names the skill rather than using the slash command, because a slash-invoked fork reports 0 turns and fails the validity gate; outcome graders read last_message."
tags: [mcp-tools, audit, outcome, discrimination, severity, fix-order]
runs: 3
max_turns: 30
timeout_seconds: 900
allowed_tools: [Skill, Bash, Read, Glob, Grep, Agent]
expected_outcome: "get_report gets C6 FAIL for reportId, C12 WARN (not FAIL) for the missing readOnlyHint and a C2/C3 gap; delete_workspace is flagged for the Cosmos DB / tombstone / partition key leak; list_items is not flagged under C10; the fix guidance lists the FAIL items first."
---

Run the mcp-tools:audit skill on servers/reports and show me its full report.

Give me the per-tool scorecard and tell me what to fix first.
