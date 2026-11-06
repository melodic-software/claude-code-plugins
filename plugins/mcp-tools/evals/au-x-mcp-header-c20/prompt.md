---
description: "C20 discrimination over four tools: resize_cluster puts x-mcp-header on a number parameter and declares Cluster and cluster, which are not case-insensitively unique (FAIL); export_report mirrors an API key into a header (WARN, not FAIL); run_query's string Region header passes; list_reports declares none and must not be flagged. An llm judge checks FAIL-first fix order. The skill runs as context: fork; the prompt names the skill rather than using the slash command, because a slash-invoked fork reports 0 turns and fails the validity gate; outcome graders read last_message."
tags: [mcp-tools, audit, outcome, x-mcp-header, discrimination, fix-order]
runs: 3
max_turns: 30
timeout_seconds: 900
allowed_tools: [Skill, Bash, Read, Glob, Grep, Agent]
expected_outcome: "resize_cluster gets C20 FAIL naming the number-typed scale parameter and the Cluster/cluster collision; export_report gets C20 WARN, not FAIL; run_query passes C20; list_reports is not flagged under C20; the C20 FAIL comes first in the fix guidance."
---

Run the mcp-tools:audit skill on servers/warehouse and show me its full report.

Give me the per-tool scorecard and tell me what to fix first.
