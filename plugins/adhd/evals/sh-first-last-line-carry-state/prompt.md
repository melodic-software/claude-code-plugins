---
description: "Hard case. With shape set, a diagnosis reply's first or last line also says what happened (the upload was denied because the role lacks s3:PutObject), not only what to do. Why hard: rules 1 and 3 put an action on both the first and the last line, so a reply that obeys them can carry the cause only in the middle, where a reader who reads the ends never sees it; only the pre-send check's 'reading only the first line and the last line, does the reader know what just happened?' asks for it at an end. The prompt does not ask what happened."
tags: [adhd, shape, outcome, state, hard]
runs: 5
max_turns: 10
timeout_seconds: 400
allowed_tools: [Skill, Read, Glob, Grep]
expected_outcome: "The reply finds that the S3 upload was denied because the invoice-export-nightly role's policy lacks s3:PutObject, and its first line or its last line states that cause (failed, denied, lacks, missing), not only an action."
---

/adhd:shape

The nightly invoice export is red again and finance needs the file by 9. Everything is in this repo (logs/ and infra/). Get me unblocked.
