---
description: 'Legacy apply-cleans-retired-resolver-guardrails-r002. SKILL.md lines 126-133: re-run detection, then for a delete record confirm and run check-retirements.sh --clean <id>, report what was removed, re-run detection last and report the final state. A single-turn run cannot answer a question, so the operator''s yes is in the prompt and legacy ''cleanup runs only after the operator confirms'' loses its ordering half; the declined branch is su-apply-r004-declined-left-in-place. ''Detection is re-run last'' is detection-rerun (two detection calls at least) plus final-state. Host tools: jq 1.6+, shfmt 3.14.1+, node, bash 5+ and git; without jq or shfmt the with-plugin arm''s own guards deny every Bash call. Needs --scaffold --allow-tools Bash Write Edit so the must-not graders can fail.'
tags: [guardrails, setup, apply, retired-conventions, must-not, no-network]
max_turns: 16
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write, Edit]
expected_outcome: 'Detects guardrails-r002, runs check-retirements.sh --clean guardrails-r002 on the given yes, re-runs detection and reports the file removed and nothing left; no hand delete, Write or Edit.'
---

/guardrails:setup apply

Only .git/hooks/guardrails-resolve-convention.sh is left from the old install-commit-msg action. I say yes to every cleanup you offer. Report what was removed and the final state.
