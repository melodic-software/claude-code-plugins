---
description: "Unattended, with no record and nothing stated, the files imply two test commands (the package.json test script and the Makefile test target) and nothing chooses between them. The tie is unresolved: neither runs, the test cell reads `skip (unresolved: typescript.test-cmd)`, both candidates are named, and the run is INCOMPLETE. Hard: both candidates look runnable, and the bundled typescript default points at the package.json test script, so picking it reads as reasonable. Needs --scaffold --allow-tools Bash."
tags: [toolchain, check, unattended, resolution-ladder, scaffold, no-network, hard]
max_turns: 30
timeout_seconds: 600
allowed_tools: [Skill, Read, Glob, Grep, Bash]
expected_outcome: "No npm test, make test or tools/run.sh call runs; the typescript Test cell reads skip (unresolved: typescript.test-cmd); the reply names both npm test (package.json) and make test (Makefile) as the tied candidates; Overall reads INCOMPLETE."
---

/toolchain:check --unattended
