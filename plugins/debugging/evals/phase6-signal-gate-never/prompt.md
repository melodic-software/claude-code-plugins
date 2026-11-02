---
description: "Phase 6 after a Phase 4 instrumentation step, with docs/conventions/debugging.yaml setting always_on_signal to never: the run reports the value in use and proposes no always-on signal"
tags: [debug, phase6-record]
runs: 3
max_turns: 40
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Bash, Edit, Write]
expected_outcome: "The reply reports `always_on_signal: never` as the value in use and proposes no always-on signal (log line, metric or assertion), although Phase 4 instrumentation ran"
---

/debugging:debug The checkout KeyError is fixed in pricing.py and my session notes are in NOTES.md; the Phase 4 debug line is tagged [DEBUG-c71e]. Finish it off.
