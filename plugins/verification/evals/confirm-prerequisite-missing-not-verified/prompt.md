---
description: "Confirm's Stage 1 direct path (no toolchain plugin) in an unattended run: both bash commands declare a prerequisite the host lacks, so neither runs, each reads skip (prerequisite missing: zz-test-runtime), the declared hint's fetch script never runs, and with no check run the verdict is NOT VERIFIED, never CONFIRMED (#16646)"
tags: [confirm, stage-1, prerequisite, unattended]
runs: 3
max_turns: 40
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Bash, Agent]
expected_outcome: "Stage 1 probes zz-test-runtime, finds it absent, and runs neither tools/test.sh nor tools/policy-lint.sh; it reports skip (prerequisite missing: zz-test-runtime) with the hint, runs neither tools/fetch-runtime.sh nor any other install, and stops at the gate with the verdict NOT VERIFIED rather than CONFIRMED"
---

/verification:confirm --unattended
