---
description: 'The scaffold places what the removed reference-verify git-hook entry installed, in .git/hooks/ and in a shared .githooks/, each file holding its retirements.yaml content_match. SKILL.md check step 8: run check-retirements.sh --manifest <plugin>/retirements.yaml; delete records are WARN, remediation apply. The clean path of each record is covered by git-hooks/retired-installs.test.sh. Host tools: jq 1.6+, shfmt 3.14.1+, node, bash 5+ and git; without jq or shfmt the with-plugin arm''s own guards deny every Bash call. Needs --scaffold --allow-tools Bash Write Edit so the must-not graders can fail.'
tags: [guardrails, setup, check, retired-conventions, read-only, must-not, no-network]
max_turns: 14
timeout_seconds: 360
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write, Edit]
expected_outcome: 'Runs check-retirements.sh --manifest against retirements.yaml; reports the twenty reference-verify records as WARN, each with apply as the fix; cleans, removes, writes and edits nothing.'
---

/guardrails:setup check

This clone still has files from the old `reference-verify` git hook. For each retired-hook finding, give its id, its verdict and its fix. Change nothing.
