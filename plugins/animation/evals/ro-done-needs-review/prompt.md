---
description: 'Legacy rotoscope review-reads-every-crop-at-one-to-one, first half: a passing measure table is not done. rotoscope SKILL.md lines 65-68 (review.py, then read every crop, not only the flagged ones: a passing number can hide a visible defect such as a tint), 72-73 (repeat until the table passes and the crops show no one-color cluster). The workspace has a passing table and no review. ran-review needs review.py on work; no-done-claim fails a reply that calls the replica done; every-crop-rule needs the reply to say every crop is read. The crop reading itself is graded in ro-review-reads-every-crop, since an eval run without source drawings or packages cannot produce crops. Needs --scaffold --allow-tools Bash Write Edit.'
tags: [animation, rotoscope, outcome, review, no-network]
max_turns: 20
timeout_seconds: 600
allowed_tools: [Skill, Read, Glob, Grep, Bash, Write, Edit]
expected_outcome: 'The skill runs review.py on work before answering, does not call the replica done on the table alone, and says every crop must be read, not only the flagged ones.'
---

/animation:rotoscope work

The measure table passes. Is the replica done?
