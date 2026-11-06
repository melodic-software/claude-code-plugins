---
description: "Hard because both pairs look alike in source: grant_repo_access declares requiresUserInteraction as the string \"true\" and the .NET ApprovePayout uses the [McpMeta(..., \"true\")] string overload, both C18 FAIL, while revoke_repo_access (JSON true) and CancelPayout (the bool overload) pass C18. The reply must say the string value is ignored, so the consent gate never fires, and an llm judge checks FAIL-first fix order. The skill runs as context: fork; the prompt names the skill rather than using the slash command, because a slash-invoked fork reports 0 turns and fails the validity gate; outcome graders read last_message."
tags: [mcp-tools, audit, outcome, meta-annotations, dotnet, discrimination, fix-order, no-network]
runs: 3
max_turns: 30
timeout_seconds: 900
allowed_tools: [Skill, Bash, Read, Glob, Grep, Agent]
expected_outcome: "C18 FAIL on grant_repo_access and ApprovePayout, C18 PASS on revoke_repo_access and CancelPayout; the reply says Claude Code ignores a value other than JSON true, so the consent gate silently never applies; the C18 FAIL items come first in the fix guidance."
---

Run the mcp-tools:audit skill on servers/consent and show me its full report.

Give me the per-tool scorecard and tell me what to fix first.
