---
description: "Bare invocation whose previous message is an aside, a regression guard. The case runs single-turn, so the conversation is summarized after the command, which makes that summary the text after the command; the truly bare branch needs prior turns and is not exercised here. The last message is a side question while a proposed task waits on the user's yes, so the reply raises that pending task rather than the side question, and executes nothing."
tags: [discipline, be-ambitious, outcome, regression-guard]
runs: 3
max_turns: 30
timeout_seconds: 900
allowed_tools: [Skill, Read, Glob, Grep, Write, Edit, Bash]
expected_outcome: "Says the previous message was a side question, raises the pending CSV export task instead, and makes no Write, Edit or Bash call."
---

/discipline:be-ambitious

The conversation so far: I asked you to add a CSV export to the invoice list page. You proposed a plan (an export button, a streaming endpoint, and tests for the column mapping) and asked "Shall I start building it?". My previous message was a side question: "Do you want me to run this command first so you can see how it behaves?"
