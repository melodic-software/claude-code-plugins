---
description: "A Python suite with one assertion-free test, one self-identical comparison and one real check. The audit runs its scanner and names both can't-fail tests without editing. Routine: guards the skill's core detect-and-report path."
tags: [testing, audit, outcome, routine, source-skill-contract]
max_turns: 20
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Skill, Bash]
expected_outcome: "Runs the bundled can't-fail scan, reports test_balance_runs (no assertion) and test_balance_matches_itself (the same expression on both sides), shows how many test files it read, and changes no file."
---
/testing:audit some tests in this repo look like they would pass whatever ledger.py does. Which ones can't fail? Don't change any files.
