---
description: "Bare invocation. The prior user message is supplied inline because the case runs single-turn; the reply takes it as the request and raises it, fences scope, and executes nothing."
tags: [discipline, be-ambitious, outcome]
runs: 3
max_turns: 30
timeout_seconds: 900
allowed_tools: [Skill, Read, Glob, Grep, Write, Edit, Bash]
expected_outcome: "Treats the quoted prior message (a photo backup script) as the request and shows it beside a raised version; a scope fence; no Write, Edit or Bash call."
---

/discipline:be-ambitious

My previous message was: "Write me a script that copies my Photos folder to my external drive every night."
