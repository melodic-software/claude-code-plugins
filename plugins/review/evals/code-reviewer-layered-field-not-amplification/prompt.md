---
description: "The branch adds phoneNumber to the Customer entity, its row mapping, its DTO, its mapper and a migration, one representation per layer: code-reviewer does not report those edits as Shotgun Surgery or change amplification at IMPORTANT or CRITICAL"
tags: [review, code-reviewer, repetition]
runs: 3
max_turns: 40
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Agent, Bash]
expected_outcome: "The review:code-reviewer agent reviews the branch and reports no Shotgun Surgery or change-amplification finding at IMPORTANT or CRITICAL for adding phoneNumber to src/domain/customer.js, src/db/customer-repository.js, src/api/customer-dto.js, src/api/customer-mapper.js and migrations/002_add_customer_phone_number.sql, because the representation each layer needs for one new field is not a site; a note explaining that is fine"
---

I added a phone number to customers on this branch.

Use the review:code-reviewer agent to review the branch against the base commit whose SHA is in `.review-base`. Ask it to write each finding on one line as `SEVERITY | file:line | finding | Confidence: level`, and give me its findings as it returned them.
