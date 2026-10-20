---
description: "The branch hardcodes the upload limit 25 in a new validator instead of importing MAX_UPLOAD_MB, and adds PayPal to three per-method files: code-reviewer rates the introduced, unsynced copy CRITICAL and the Shotgun Surgery change no higher than SUGGESTION"
tags: [review, code-reviewer, repetition]
runs: 3
max_turns: 40
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Agent, Bash]
expected_outcome: "The review:code-reviewer agent reports as CRITICAL that src/upload/validate.js hardcodes 25, a copy of MAX_UPLOAD_MB in src/config.js, so raising the limit there leaves the validator rejecting files the upload hint allows; the fix imports the constant. Adding paypal to src/payments/options.js, labels.js and icons.js is reported as Shotgun Surgery at SUGGESTION, never CRITICAL or IMPORTANT"
---

I added an upload size check and PayPal as a payment method on this branch.

Use the review:code-reviewer agent to review the branch against the base commit whose SHA is in `.review-base`. Ask it to write each finding on one line as `SEVERITY | file:line | finding | Confidence: level`, and give me its findings as it returned them.
