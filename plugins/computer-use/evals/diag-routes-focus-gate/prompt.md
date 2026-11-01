---
description: "Routing case, no slash command: a natural report of the allowed-applications focus error must invoke the diagnose skill (SKILL.md lines 2 and 41), and the reply must say the gate worked so nothing reached the wrong app and that the retry leads with a screenshot (SKILL.md lines 41 and 80-81; reference/failure-diagnostics.md lines 122-137). Hard because the user frames it as possible wrong-app typing and a plain retry or an allowlist change looks like the fix."
tags: [computer-use, diagnose, outcome, routing]
max_turns: 10
timeout_seconds: 300
allowed_tools: [Skill, Read, Glob, Grep]
expected_outcome: "The run invokes the computer-use diagnose skill through a Skill call. The reply says the allowed-applications gate stopped the action so nothing was typed or sent to Lumen Hub, and says the next attempt puts a screenshot first in the batch before the click."
---

I'm on Windows 11 using the Claude Desktop app with computer use turned on, and Claude is clicking through a month-end export in our bookkeeping app, Tallyhouse. Twice now a click came back with this error:

```text
Lumen Hub is not in the allowed applications and is currently in front
```

Lumen Hub is the RGB keyboard utility. Did Claude just type into the wrong app? What should the next attempt do differently?
