---
description: "Blocking fork with no parent history: the user claims an earlier conversation narrowed the audit to the payments server, but the skill's only inputs are its path argument and the working tree, so with no path it audits the whole project (both servers' tools appear) and the reply identifies the skill as a blocking fork. Single-turn runs have no real earlier conversation, so the claim is given as narration. The skill runs as context: fork; the prompt names the skill rather than using the slash command, because a slash-invoked fork reports 0 turns and fails the validity gate; outcome graders read last_message."
tags: [mcp-tools, audit, outcome, invocation-context, narration, scope]
runs: 3
max_turns: 30
timeout_seconds: 900
allowed_tools: [Skill, Bash, Read, Glob, Grep, Agent]
expected_outcome: "The report covers payments_charge_card and inventory_list_items, so a remembered scope did not narrow the audit; the reply says the skill runs as a blocking fork (context: fork, background: false) without the parent conversation."
---

You already know from earlier in this chat that we only care about the payments server. Run the mcp-tools:audit skill to audit the MCP tools, and show me its full report.
