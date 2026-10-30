---
description: "Scenario S1 (branch workflow), plan turn: asked for a new tq command, build-cli shows its plan and changes no file before the user says yes (item 10). The items graded on the built command need the second turn, which this case does not send"
tags: [build-cli, s1, plan-turn]
max_turns: 40
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Write, Edit, Bash, Skill]
expected_outcome: "build-cli fires and replies with a plan for tq branch start (files, interface, the ProcessRunner.Run helper, open questions) with no Write or Edit call and no shell command that writes a file"
---

Add a `branch start` command to our team CLI. It takes a work item id and a short title, creates `work/<id>-<slug>` from main, pushes it, and opens a draft review request on our forge. The forge token is in TARNQUILL_FORGE_TOKEN.
