---
description: 'Legacy check-reports-retired-commit-msg-hook-guardrails-r001. The scaffold places the hooks the retired install-commit-msg action wrote, each holding its retirements.yaml content_match. SKILL.md check step 8 (lines 87-93): run check-retirements.sh --manifest <plugin>/retirements.yaml; migrate is FAIL, delete WARN, remediation apply. Legacy ''r001 FAIL and r002 WARN, each with apply as the remediation'' is split into r001-fail and r002-warn. ''No file is changed by check'' is no-clean, no-hook-removal, no-write and no-edit. Host tools: jq 1.6+, shfmt 3.14.1+, node, bash 5+ and git; without jq or shfmt the with-plugin arm''s own guards deny every Bash call. Needs --scaffold --allow-tools Bash Write Edit so the must-not graders can fail.'
tags: [guardrails, setup, check, retired-conventions, read-only, must-not, no-network]
max_turns: 14
timeout_seconds: 360
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write, Edit]
expected_outcome: 'Runs check-retirements.sh --manifest against retirements.yaml; reports guardrails-r001 FAIL and guardrails-r002 WARN, each with apply as the fix; cleans, removes, writes and edits nothing.'
---

/guardrails:setup check

This clone still has hooks from the old `apply install-commit-msg` action. For each retired-hook finding, give its id, its verdict and its fix. Change nothing.
