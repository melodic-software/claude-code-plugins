---
description: "Outcome case for /knowledge:distill Phase 5 (quality polish): the testing skill was distilled from books/field-notes-on-retries.pdf through Phase 4, and reference/idempotency.md holds one line while Chapter 2 states the key header, the 24-hour retention, 409 for an in-flight replay and 422 for a reused key. A polish pass that does its job brings those specifics into idempotency.md. Measures whether dropping the 'Thin section audit' bullet (re-read files that felt rushed) loses that outcome: compare the with-arm across the two skill versions. Read-only plus Write and Edit, so it runs without a shell sandbox; the progress file lives under the plugin data directory, which the scaffold cannot reach, so the prompt states the phase."
tags: [knowledge, distill, outcome, scaffold, phase-5]
runs: 3
max_turns: 30
timeout_seconds: 900
allowed_tools: [Skill, Read, Glob, Grep, Write, Edit]
expected_outcome: "The run edits or rewrites .claude/skills/testing/reference/idempotency.md so it carries at least one Chapter 2 specific it lacked (the Idempotency-Key header, 24-hour retention, 409 Conflict for an in-flight replay, or 422 for a reused key)."
---

/knowledge:distill Phases 1 to 4 are done for books/field-notes-on-retries.pdf into the testing skill at .claude/skills/testing (both chapters distilled, routing table and decision guide written, links checked). Run Phase 5 quality polish on it now, apply what it finds, and report what you changed.
