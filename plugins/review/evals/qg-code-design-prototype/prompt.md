---
description: "A prototype branch hardcodes the 25 MB upload cap in two new files instead of reading MAX_UPLOAD_MB, reviewed with --quality-bar prototype: the code-design review reports the repetition as SUGGESTION, never CRITICAL or IMPORTANT"
tags: [review, quality-gate, code-design, repetition, quality-bar]
runs: 3
max_turns: 40
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Agent, Bash, Write, Edit]
expected_outcome: "The gate dispatches review:brief-reviewer with the line Quality bar: prototype and reports that app/upload.py and app/form.py each hardcode 25, a copy of MAX_UPLOAD_MB in config.py, rated SUGGESTION because the quality bar is prototype. No finding is CRITICAL or IMPORTANT, and nothing is edited"
---

This is a throwaway prototype. I added the upload check and form hint on this branch.

Run `/review:quality-gate code-design` on this branch with `--base` set to the SHA in `.review-base`, `--quality-bar prototype` and `--report-only`, and give me the report.
