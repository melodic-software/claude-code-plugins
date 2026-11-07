---
description: "setup apply with a gitignored personal override (judge_samples 5) beside the retired .claude/provenance.local.json (attribution-r002: judge_samples 3, trigger_less_stamp_check true). Detection reports r002 as FAIL; the override keeps judge_samples 5 because the current file wins and gains trigger_less_stamp_check, written or proposed per key; with no operator confirmation in this run, --clean does not run. Needs --scaffold --allow-tools Bash Write Edit. r002-fail-label checks the FAIL label deterministically: attribution-r002 or its file beside FAIL on the same or next line, with no WARN or INFO on the record line."
tags: [attribution, setup, outcome, retirements, write-posture]
max_turns: 15
timeout_seconds: 300
allowed_tools: [Read, Glob, Grep, Bash, Write, Edit]
expected_outcome: "The reply reports .claude/provenance.local.json (attribution-r002) as FAIL. Any write to docs/conventions/attribution.local.yaml keeps judge_samples 5 and adds trigger_less_stamp_check true, or the reply proposes exactly that per key. No --clean and no removal of the retired file runs: the operator has not confirmed."
---

/attribution:setup apply
