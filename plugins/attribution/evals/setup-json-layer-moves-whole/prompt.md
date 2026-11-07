---
description: "setup set stamp_expiry_days 90 with only the retired .claude/attribution.json (attribution-r003: excluded_paths, budgets.corpus_fetch_ceiling) and no YAML team layer. Detection reports it as a FAIL to migrate, not a layer the detectors read; the new docs/conventions/attribution.yaml carries every JSON key unchanged beside stamp_expiry_days 90 and is shown before any write (SKILL.md lines 60-66); --clean does not run without the operator's confirmation. Needs --scaffold --allow-tools Bash. r003-fail-label checks the FAIL label deterministically: attribution-r003 or its file beside FAIL on the same or next line, with no WARN or INFO on the record line."
tags: [attribution, setup, outcome, retirements, write-posture]
max_turns: 15
timeout_seconds: 300
allowed_tools: [Read, Glob, Grep, Bash]
expected_outcome: "The reply reports .claude/attribution.json (attribution-r003) as a retired config to migrate at FAIL, not as a layer in effect, and shows a docs/conventions/attribution.yaml carrying excluded_paths and budgets.corpus_fetch_ceiling unchanged with stamp_expiry_days 90 before any write. No --clean and no removal of the retired file runs."
---

/attribution:setup set stamp_expiry_days 90
