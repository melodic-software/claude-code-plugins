---
description: "An interview whose first decision opens later ones: round 1 asks only the ready questions and its header carries one Later: line naming the topics of the rounds to come. Why hard: the habit is either to ask every question at once or to say nothing about what follows"
tags: [interview, round-header, scaffold, no-network]
runs: 3
max_turns: 20
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write]
expected_outcome: "Round 1 asks the ready questions (for example whether to run the stream beside the CSV export or replace it in one cut) and its header carries one line starting `Later:` that names the topics of later rounds, such as the broker, the message schema or the cutover order"
---

/planning:interview me We want to replace the nightly CSV export in `export/nightly.py` with an event stream to the warehouse team. Nothing is decided. Whether we run both side by side or cut over at once decides most of the rest: which broker, what the message schema is, and the cutover order all depend on it. Ask round 1 and stop for my answers.
