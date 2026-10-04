---
description: "Phase 6 gate on a real repo: tagged instrumentation removed and grep-verified, Phase 1 loop re-run, hypothesis recorded for the commit or PR"
tags: [debug, converted]
runs: 3
max_turns: 40
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Bash, Edit, Write]
expected_outcome: "Every [DEBUG-a4f2] line is gone from pricing.py and checkout.py with the fix intact, repro_checkout.py was re-run, and the reply states the confirmed hypothesis for the commit message or PR description"
---

/debugging:debug I've applied the fix and my debug logs are tagged [DEBUG-a4f2]. What's left before I can call this done? Take it the rest of the way.
