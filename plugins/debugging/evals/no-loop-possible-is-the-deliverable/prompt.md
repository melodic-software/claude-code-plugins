---
description: "When no loop can be built, stop, say so, list what was tried, and ask for access or a captured artifact"
tags: [debug, converted]
runs: 3
max_turns: 15
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: "States that no reproduction loop can be built yet, lists the strategies considered, asks for environment access, a captured artifact or instrumentation permission, and does not hypothesize causes"
---

/debugging:debug users report the app 'sometimes feels laggy' — I have no way to reproduce it, no logs, no access to their environment, and no capture.
