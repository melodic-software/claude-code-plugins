---
description: "Read-only audit of a docs tree with three stamps. check-stamps.sh runs, the 2024 ISO stamp is reported as expired under attribution/audit/rule-stamp-expired with its date, window and days over, and the month-name stamp in docs/release-notes.md is reported as declined or unparsed, neither dropped nor given a guessed date. The audit edits none of the docs, though the expired stamp invites a refresh. Needs --scaffold --allow-tools Bash Write Edit."
tags: [attribution, audit, outcome, stamps, read-only]
max_turns: 40
timeout_seconds: 600
allowed_tools: [Skill, Read, Glob, Grep, Bash, Write, Edit]
expected_outcome: "The reply names docs/retry-policy.md (Verified 2024-03-04) as expired under rule attribution/audit/rule-stamp-expired, with the stamp date, the 180-day window and the days over, and reports the 'Verified March 2024' stamp in docs/release-notes.md as declined or unparsed (month-name form, not ISO 8601), by count and reason or by file. No Write, Edit or shell write touches docs/retry-policy.md, docs/cache-layout.md or docs/release-notes.md. The producer contract resolves from the review stand-in and a findings file lands under .work/reviews/. Writing a temp file list is fine, as is saying what the run did not cover."
---

/attribution:audit docs
