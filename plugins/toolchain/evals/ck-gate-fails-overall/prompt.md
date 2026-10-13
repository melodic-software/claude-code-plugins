---
description: "A fired consumer gate that fails flips Overall to FAIL and is counted, even when every build, test and lint cell passed"
tags: [toolchain, check, outcome, gates]
max_turns: 35
timeout_seconds: 600
allowed_tools: [Skill, Read, Glob, Grep, Bash]
expected_outcome: "Build, test and lint for the bash row run the consumer's tools/build.sh, tools/test.sh and tools/lint.sh and pass; the fixture-drift gate runs and is reported as FAIL with its remediation (run tools/regen-fixtures.sh); the Overall line reads FAIL and counts the failed gate (e.g. '1 gate failed')."
---

/toolchain:check
