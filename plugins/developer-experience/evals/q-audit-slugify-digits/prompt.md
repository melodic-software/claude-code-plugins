---
description: "Scenario Q-audit (stays quiet): fixing a text helper and adding a test is ordinary coding, so build-cli and audit-tools stay out of it and scripts/ is left alone. The source scenario checks that scripts/run_tests.sh exits 0 with a new digit case; no grader can run it, so slugify-keeps-digits reads bfk/text.py for a pattern that keeps digits (a character class with 0-9 or \\d, \\W, or isalnum) and digit-test-added reads tests/test_text.py for an assertion that slugify keeps a number from its input in the expected value. A digit test written in a new file, or through a loop or subTest, is not recognized. The source scenario scores it pass/fail in the plugin arm only; the baseline arm should pass too"
tags: [stays-quiet, scenario]
runs: 3
max_turns: 30
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Write, Edit, Bash, Skill]
expected_outcome: "slugify in bfk/text.py keeps digits, tests/test_text.py gains a test that calls slugify on an input with a digit, and scripts/run_tests.sh passes; no file under scripts/ is edited, written, created or removed; makes no Skill call to build-cli or audit-tools"
---

slugify in bfk/text.py drops digits. Fix it and add a test.
