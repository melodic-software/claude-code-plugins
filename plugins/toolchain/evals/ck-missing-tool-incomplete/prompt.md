---
description: "A lint tool absent from PATH is an environment skip, never FAIL, and leaves the run INCOMPLETE, never PASS"
tags: [toolchain, check, outcome, missing-tool]
max_turns: 30
timeout_seconds: 600
allowed_tools: [Skill, Read, Glob, Grep, Bash]
expected_outcome: "The bash row's Lint cell reads skip (tool missing: zzlint-not-installed), not FAIL; the Overall line reads INCOMPLETE and names zzlint-not-installed as the cause; Overall never reads PASS or FAIL."
---

/toolchain:check
