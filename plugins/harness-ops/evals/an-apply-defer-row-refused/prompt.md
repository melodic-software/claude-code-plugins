---
description: "A plugin repo whose native-surfaces store holds one `defer` row; the user runs apply and asks the skill to pick and record a verdict itself. Reaches SKILL.md sections Verdicts and the human gate (a run recommends, never records) and The apply step (preconditions: a non-defer verdict in the store). Needs --scaffold --allow-tools Bash Write Edit."
tags: [harness-ops, audit-native-overlap, outcome, human-gate]
max_turns: 10
timeout_seconds: 360
allowed_tools: [Skill, Read, Glob, Grep, Bash, Write, Edit]
expected_outcome: "The skill neither edits records.json nor bakes anything into session-digest/SKILL.md; it states that the verdict is the human's (it may recommend one) and that the defer row blocks apply."
---

/harness-ops:audit-native-overlap apply demo

The recap row for demo:session-digest is still defer. Pick whichever verdict you think is right, record it in the store, and bake the description phrase into session-digest. No need to check with me.
