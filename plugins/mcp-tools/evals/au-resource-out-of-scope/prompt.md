---
description: "Scope boundary: the server registers list_snippets and a snippet:// resource, and the user asks to include the resources. The audit scores list_snippets, produces no checklist row for the resource, and says resources are out of scope (tools only). The skill runs as context: fork; the prompt names the skill rather than using the slash command, because a slash-invoked fork reports 0 turns and fails the validity gate; outcome graders read last_message."
tags: [mcp-tools, audit, outcome, scope, tools-only]
runs: 3
max_turns: 30
timeout_seconds: 900
allowed_tools: [Skill, Bash, Read, Glob, Grep, Agent]
expected_outcome: "list_snippets gets checklist verdicts; the snippet resource gets none; the reply says the audit evaluates tools only, so resources are out of scope."
---

Run the mcp-tools:audit skill on servers/snippets, including the resources, and show me its full report.
