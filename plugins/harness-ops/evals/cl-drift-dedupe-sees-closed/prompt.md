---
description: "One question about the changelog skill's native-drift step: its duplicate check lists issues in every state with a raised limit (`gh issue list --state all --limit 1000`), so a closed match is found even with 200 open issues. Reaches context/native-drift.md (dedupe step and its recorded fact). Source: the consumer's own writing. routine. Needs --allow-tools Bash for the pre-computed line. Held-rows rows: harness-ops 50."
tags: [harness-ops, changelog, reference-answer, routine]
max_turns: 15
timeout_seconds: 300
allowed_tools: [Skill, Read, Glob, Grep, Bash]
expected_outcome: "No apply runs. The answer says the check lists issues in all states (closed included) with a 1000 limit, above the 30 default, so the closed issue is found."
---

/harness-ops:changelog quick question about the native-drift step in apply: before it files an item it checks for an existing one. We closed a matching issue last month and have about 200 open issues. Will that check find the closed one? Answer only, don't run apply.
