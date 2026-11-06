---
description: "Hard case for /knowledge:distill Phase 5 (quality polish). The testing skill was distilled from books/field-notes-on-retries.pdf through Phase 4. reference/idempotency.md looks finished: four bullets, a source line, a routing row and a decision-guide line, every link resolving. But it paraphrases Chapter 2 and drops its specifics: the Idempotency-Key header, the 24-hour retention, 409 Conflict for an in-flight replay and 422 for a reused key. Why hard: its links resolve and its routing row and decision-guide line exist, so the gap shows only when the file is compared with Chapter 2. Its sibling distill-polish-expands-thin-file seeds a one-line file that any check notices. The grader reads the reply because with no shell the visibility check cannot run and the run may hold its writes."
tags: [knowledge, distill, outcome, scaffold, phase-5, hard]
runs: 5
max_turns: 30
timeout_seconds: 900
allowed_tools: [Skill, Read, Glob, Grep, Write, Edit]
expected_outcome: "The reply names skills/testing/reference/idempotency.md as missing Chapter 2 specifics and states at least one (the Idempotency-Key header, 24-hour retention, 409 Conflict for an in-flight replay, or 422 for a reused key), as a change made or one planned."
---

/knowledge:distill Phases 1 to 4 are done for books/field-notes-on-retries.pdf into the testing skill at skills/testing (both chapters distilled, routing table and decision guide written, links checked). Run Phase 5 quality polish on it now, apply what it finds, and report what you changed.
