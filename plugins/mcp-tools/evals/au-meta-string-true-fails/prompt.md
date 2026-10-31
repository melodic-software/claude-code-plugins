---
description: "Hard because the declared value looks right: requiresUserInteraction is the string \"true\", which the checklist grades C18 FAIL, while the missing readOnlyHint on the read-only tool is C12 WARN, never FAIL. The report keeps its Overall counts line. The skill runs as context: fork; the prompt names the skill rather than using the slash command, because a slash-invoked fork reports 0 turns and fails the validity gate; outcome graders read last_message."
tags: [mcp-tools, audit, outcome, meta-annotations, severity, output-contract, au-1]
runs: 3
max_turns: 30
timeout_seconds: 900
allowed_tools: [Skill, Bash, Read, Glob, Grep, Agent]
expected_outcome: "approve_refund gets C18 FAIL because \"anthropic/requiresUserInteraction\" is the string \"true\", not JSON true; get_refund_status gets C12 WARN (not FAIL) for its missing readOnlyHint; the report carries an Overall line counting pass, warn, fail and info."
---

Run the mcp-tools:audit skill on servers/billing and show me its full report.

We're about to ship the refund approval tool. How do the tool definitions look?
