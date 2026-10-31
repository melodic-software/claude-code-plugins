---
description: "The only checks live in checks/ledger_checks.py, a name the scanner's adapters do not claim, so the scan reads 0 test files. Hard: a model tends to read 'no findings' as a clean suite; the contract says a scan of nothing is never a clean bill."
tags: [testing, audit, outcome, hard, source-skill-contract]
max_turns: 20
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Skill, Bash]
expected_outcome: "Runs the can't-fail scan, reports that it examined 0 test files so the result is not a clean bill, and changes no file."
---
/testing:audit are any of our tests vacuous? I want a yes or no I can trust before I merge.
