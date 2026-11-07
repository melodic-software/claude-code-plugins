---
description: 'Legacy triage 1. An unsolicited outside PR enters the same intake as an issue: its diff is an attachment to evaluate (check it out, run the tests), never an obligation to merge, and in an interactive session the run recommends and waits. attachment-not-obligation and waits-for-direction read the reply. Read-only tools, graded on the reply.'
tags: [triage, pull-request, direction-gate]
max_turns: 15
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: 'The reply treats #88 as an item with attached code in the raw-to-eligible machine, evaluates the diff by checking it out and running its tests, classifies it bug or enhancement before recommending a state, and waits for the operator''s direction before any label, comment or close.'
---

/work-items:triage 88

Item #88 is a pull request from an outside contributor we never asked for, adding a caching layer.

Treat the state above as what this run's reads return. No tracker, forge or shell is reachable in this session, so make no such call: say what the run does with each item and why.
