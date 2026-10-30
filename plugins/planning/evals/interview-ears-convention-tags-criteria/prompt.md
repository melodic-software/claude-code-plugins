---
description: "The repository's convention home sets acceptance_criteria_format to ears: the locked Brief's acceptance criteria carry the bracketed EARS pattern tags, resolved through the plugin's authoring-formats ladder"
tags: [interview, conventions, ears, acceptance-criteria, scaffold]
runs: 3
max_turns: 30
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write, Edit]
expected_outcome: "The interview resolves acceptance_criteria_format to ears from docs/conventions/authoring-formats/README.md, and .work/export-retry/PLAN.md lists acceptance criteria as '- AC<n>: [<pattern>] ...' plain bullets, each tagged with one of ubiquitous, event-driven, state-driven, unwanted-behavior or optional-feature"
---

/planning:interview lock

This run is unattended: nobody will answer questions, so record anything only I can decide as blocked and keep going.

Lock the Brief. Use the topic slug `export-retry`.

Goal: the nightly CSV export retries a failed upload to the storage bucket instead of dropping the file. This goes to production.

Acceptance: when an upload fails, the export retries it up to three times, waiting 30 seconds between tries. If the third retry fails, the export writes an error line to `logs/export.log` and exits non-zero. While a retry is pending, the export does not start the next file. A successful upload deletes the local CSV.
