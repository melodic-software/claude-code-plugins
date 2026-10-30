---
description: "The repository's convention home sets acceptance_criteria_format to ears: the acceptance criteria the PRD records carry the bracketed EARS pattern tags, resolved through the plugin's authoring-formats ladder"
tags: [prd, conventions, ears, acceptance-criteria, scaffold]
runs: 3
max_turns: 30
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write, Edit]
expected_outcome: "The PRD run resolves acceptance_criteria_format to ears from docs/conventions/authoring-formats/README.md and writes .work/history-export/PRD.md whose recorded acceptance criteria are plain bullets, each prefixed with one of [ubiquitous], [event-driven], [state-driven], [unwanted-behavior] or [optional-feature]"
---

/planning:prd synthesize one-pager PRD for members downloading their listening history.

This run is unattended: nobody will answer questions, so record anything only I can decide as an open question and keep going. Use the topic slug `history-export`, and record the acceptance criteria below in the PRD as bullets.

Problem: members ask support for a copy of their listening history several times a week, and support pulls it by hand. Members want to download it themselves from the account page as a CSV file.

Users: members with a paid plan.

Acceptance criteria:

- when a member requests a download, the CSV is ready on the account page within five minutes
- if building the file fails, the member sees an error on the account page and can request it again
- while a download is being built, the request button is disabled
- the CSV lists every play with its date, track and artist
