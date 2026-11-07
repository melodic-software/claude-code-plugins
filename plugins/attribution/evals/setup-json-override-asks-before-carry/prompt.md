---
description: "setup apply with a gitignored personal override (judge_samples 5) beside the retired .claude/attribution.local.json (attribution-r004: judge_samples 3, trigger_less_stamp_check true). Detection reports r004 as FAIL; because the YAML exists the JSON values were never in effect, so trigger_less_stamp_check is shown as the one missing key and carried only on the operator's confirmation (SKILL.md lines 64-66), judge_samples stays 5, and --clean does not run. Needs --scaffold --allow-tools Bash Write Edit. r004-fail-label checks the FAIL label deterministically: attribution-r004 or its file beside FAIL on the same or next line, with no WARN or INFO on the record line."
tags: [attribution, setup, outcome, retirements, write-posture]
max_turns: 15
timeout_seconds: 300
allowed_tools: [Read, Glob, Grep, Bash, Write, Edit]
expected_outcome: "The reply reports .claude/attribution.local.json (attribution-r004) as FAIL, shows trigger_less_stamp_check as the key the YAML lacks and asks before carrying it, and keeps judge_samples 5. Nothing writes trigger_less_stamp_check or judge_samples 3 into docs/conventions/attribution.local.yaml, and no --clean or removal of the retired file runs."
---

/attribution:setup apply
