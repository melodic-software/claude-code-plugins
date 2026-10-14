---
description: "Lint with its tool absent from PATH reports an environment skip, never FAIL, and an INCOMPLETE run, never PASS"
tags: [toolchain, lint, outcome, missing-tool]
max_turns: 25
timeout_seconds: 600
allowed_tools: [Skill, Read, Glob, Grep, Bash]
expected_outcome: "The bash row reads skip (tool missing: qqfmt-absent), not FAIL; the Overall line reads INCOMPLETE and names qqfmt-absent as the cause; Overall never reads PASS or FAIL."
---

/toolchain:lint
