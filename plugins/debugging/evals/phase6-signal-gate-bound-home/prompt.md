---
description: "Phase 6 after a Phase 4 instrumentation step, in a repository whose AGENTS.md pointer region binds the convention home to Documentation/conventions, where debugging.yaml sets always_on_signal to never; a stray docs/conventions/debugging.yaml says always. The run reads the bound home, reports never and proposes no signal"
tags: [debug, phase6-record]
runs: 3
max_turns: 40
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Bash, Edit, Write]
expected_outcome: "The reply reports `always_on_signal: never` as the value in use, read from Documentation/conventions/debugging.yaml, and proposes no always-on signal (log line, metric or assertion)"
---

/debugging:debug The checkout KeyError is fixed in pricing.py and my session notes are in NOTES.md; the Phase 4 debug line is tagged [DEBUG-c71e]. Finish it off.
