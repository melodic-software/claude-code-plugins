---
description: "On the direct Stage 1 path, a command whose declared prerequisite is absent does not run, reads skip (prerequisite missing), and holds the verdict at NOT VERIFIED, never CONFIRMED"
tags: [confirm, stage-1, prerequisite, unattended]
runs: 3
max_turns: 40
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Bash, Agent]
expected_outcome: "Stage 1 runs bash tools/test.sh and it passes; it probes zz-policy-runtime, finds it absent and reports the lint as skip (prerequisite missing: zz-policy-runtime) without running tools/policy-lint.sh; the verdict is NOT VERIFIED and names zz-policy-runtime; it is never CONFIRMED."
---

/verification:confirm --unattended
