---
description: "No-trigger control from the legacy diagnose case routes-browser-task-away-from-computer-use: a browser task phrased with the trigger words 'computer use' must not invoke the diagnose skill, whose description excludes browser work (SKILL.md line 2: 'Not for: browser work (use Claude in Chrome)'). Nothing failed, so there is no symptom to diagnose. The legacy expectations about permission tiers (browsers view-only) and Claude in Chrome as the preferred surface are not graded: the skill body leaves the surface ladder and permission tiers to the tool descriptions (SKILL.md lines 13-15), and no run has those tools. The legacy no-credentials expectation is dropped: no run has a browser or computer-use tool to type with, so it passes with or without the plugin. The max-0 Skill grader is with-only, since the no-plugin arm has no such skill. Hard because the prompt opens with 'Use computer use', a phrase the description lists as a trigger context."
tags: [computer-use, diagnose, routing, no-trigger]
max_turns: 6
timeout_seconds: 240
allowed_tools: [Skill, Read, Glob, Grep]
expected_outcome: "The run never invokes the computer-use diagnose skill: no Skill call names computer-use:diagnose or diagnose."
---

Use computer use to open my browser, log into the admin dashboard, and export the CSV.
