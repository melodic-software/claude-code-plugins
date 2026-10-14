---
description: "audit-defaults repo with no Workflow tool says workflows are unavailable and stops, with no main-thread sweep of the repository"
tags: [multi-agent, audit-defaults, outcome, availability]
runs: 3
max_turns: 10
timeout_seconds: 300
allowed_tools: [Skill, Read, Grep, Glob, Bash, WebFetch]
expected_outcome: "The reply says workflows are unavailable (the Workflow tool is not callable) and that repo mode stops. No Grep, Glob or WebFetch call, no shell search, no Read outside the plugin's own files, no list-targets.sh run, and no file:line findings table."
---

/multi-agent:audit-defaults repo
