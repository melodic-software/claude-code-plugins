---
description: 'Legacy delta 1. When nothing moved since the baseline, delta says so briefly with the window and the suppressed count, re-lists no standing finding and pads nothing. nothing-moved and suppressed-two read the reply. Read-only tools plus Bash for the skill''s pre-computed context line (needs --allow-tools Bash), graded on the reply.'
tags: [delta, quiet-run]
max_turns: 15
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill, Bash]
expected_outcome: 'The reply diffs the current detector output against the stored baseline, finds nothing moved, and says so briefly with the window it covered (since the 2026-10-31 run) and the suppressed count (2, the two low-confidence candidates under the noise budget). It does not re-list the three standing open findings or restate the previous run''s candidate set, and does not pad the report.'
---

/instruction-placement:delta

This branch's memory-tier home holds a spine baseline and a findings artifact, both from the audit run on 2026-10-31. The artifact carries three open findings (IP-001 to IP-003), none of them declined, and no suppression file exists. The detector's output today matches the baseline section for section and every rule glob still resolves. Two new candidates appear, both low-confidence and low-value, which puts them under the default noise budget. Nothing else differs.

Treat the state above as what this run's reads and scripts return. The repository is not checked out in this session, so run nothing against it: say what the run does, in order, and give its report.
