---
description: "No fabricated findings: miro_archive_board states what, when and returns, describes boardId with a format example, and declares readOnlyHint, destructiveHint and idempotentHint to fit an archive. The report must carry no FAIL verdict, an Overall line with 0 fail, and PASS on C1-C3, C7 and C12-C14. The skill runs as context: fork; the prompt names the skill rather than using the slash command, because a slash-invoked fork reports 0 turns and fails the validity gate; outcome graders read last_message."
tags: [mcp-tools, audit, outcome, no-fabrication, regression-guard]
runs: 3
max_turns: 30
timeout_seconds: 900
allowed_tools: [Skill, Bash, Read, Glob, Grep, Agent]
expected_outcome: "miro_archive_board is PASS-dominant with no FAIL verdict; the Overall line counts 0 fail; C1, C2, C3, C7 and the C12-C14 annotations pass."
---

Run the mcp-tools:audit skill on servers/boards and show me its full report.

Is miro_archive_board well-designed, or does it need work?
