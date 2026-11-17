---
description: "A command whose declared prerequisite is absent does not run, reads skip (prerequisite missing), and leaves the run INCOMPLETE, never PASS or FAIL"
tags: [toolchain, check, outcome, prerequisite]
max_turns: 30
timeout_seconds: 600
allowed_tools: [Skill, Read, Glob, Grep, Bash]
expected_outcome: "The bash row's Test cell reads pass and its Lint cell reads skip (prerequisite missing: zz-policy-runtime); tools/policy-lint.sh never runs; the Overall line reads INCOMPLETE and names zz-policy-runtime; Overall never reads PASS or FAIL."
---

/toolchain:check
