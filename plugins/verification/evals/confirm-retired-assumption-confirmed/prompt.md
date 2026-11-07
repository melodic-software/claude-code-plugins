---
description: 'Legacy assumption-retired-01. An assumption retired by an approved re-plan is listed as retired, not falsified, and withholds nothing, so with AC1 met the verdict is CONFIRMED (context/outcome.md Assessment, Assumptions line). Framed like the existing narration cases; Agent is granted so the fresh-context verifier can render the verdict. lists-retired, verdict-confirmed grade the reply; retired-not-falsified (llm) legacy expectations 1 to 3 verbatim.'
tags: [verification, confirm, narration, no-network, outcome, assumptions, hard]
max_turns: 15
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Skill, Agent]
expected_outcome: 'Intent source is the PLAN.md Brief; AC1 is met; the batch-upload assumption is retired by the approved re-plan and the single-file one holds; no replan question; the verdict is CONFIRMED.'
---

/verification:confirm. Do not read the repository, launch, install or run anything; treat these as facts. The approved PLAN.md Brief for this branch states the Problem: client photos are lost when a laptop dies. Goal: a nightly job uploads every new photo. Intent (why, in the user's words): "we never lose a client's photos again". Acceptance criterion AC1: every photo added since the last run is in storage after the nightly job. Its `### Load-bearing assumptions` table has two rows: `RETIRED 2026-10-02, re-plan approved: The storage SDK offers a batch upload call | Brief | Phase 2 Sanity Check | Major: stop and replan` and `Uploads of one file succeed or raise | SDK reference | Phase 2 Sanity Check | Moderate`. PLAN.md's Decisions table records the user approving the 2026-10-02 re-plan that replaced batch upload with one `upload_file(path)` call per photo. The change uploads each new photo with `upload_file`; its test uploads three new photos and finds all three in storage, and a test with a failing upload sees the error raised. Build, tests and lint pass. Write the report and verdict, then stop.
