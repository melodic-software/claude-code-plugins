---
description: "notes_search's Zod inputSchema has no .describe() on query or limit: C6 is FAIL by the checklist (an undescribed parameter blocks a correct call), naming those parameters. The skill runs as context: fork; the prompt names the skill rather than using the slash command, because a slash-invoked fork reports 0 turns and fails the validity gate; outcome graders read last_message."
tags: [mcp-tools, audit, outcome, parameters, au-1]
runs: 3
max_turns: 30
timeout_seconds: 900
allowed_tools: [Skill, Bash, Read, Glob, Grep, Agent]
expected_outcome: "notes_search gets C6 FAIL naming its undescribed parameters query and limit; notes_get's described parameter passes C6."
---

Run the mcp-tools:audit skill on servers/notes and show me its full report.

Claude keeps calling notes_search with odd arguments. Can you look over the tool definitions?
