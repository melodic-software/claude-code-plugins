---
description: "Contract case for the wayfind skill when the user arrives mid-flow and is unsure where the map leaves the work. Why hard: with no map state given, naming a specific charting or planning step is a guess."
tags: [wayfind, handoff]
runs: 3
max_turns: 12
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: "The user is pointed to the workflow navigator that works out the right next stage for them, instead of being handed a guessed specific pipeline step"
---

Use the wayfind skill. The tracker is unreachable from here, so work from what I say and do not look for files. I came into this session midway through an effort to rework our onboarding emails. A decision map may exist, but I don't know whether it is charted, half worked or closed. I'm unsure where this leaves the work. What should I run next?
