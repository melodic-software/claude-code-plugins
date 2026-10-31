---
description: "The repository's convention home sets acceptance_criteria_format to ears: the locked Brief's acceptance criteria carry the bracketed EARS pattern tag after each AC id"
tags: [interview, acceptance-criteria, ears, convention]
runs: 3
max_turns: 25
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Bash]
expected_outcome: "The Brief's acceptance criteria use the '- AC<n>: [<pattern>] <criterion>' shape with tags from the five EARS names, such as [event-driven] and [unwanted-behavior]"
---

/planning:interview lock

This run is unattended: nobody will answer questions, so record anything only I can decide as blocked and keep going. Use the topic slug `upload-manifest`. Print the full Brief in your reply.

When a user uploads a file to a project, rewrite the project's manifest so it lists the new file.

Goal: the manifest always matches the project's uploaded files.

Constraints: no new dependencies; the manifest stays JSON.

Acceptance criteria:

- AC1: When an upload completes, the manifest lists the uploaded file.
- AC2: If an upload fails, the manifest is left unchanged.
