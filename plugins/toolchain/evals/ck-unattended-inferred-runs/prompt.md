---
description: "Unattended, with no record and nothing stated: the package.json test script is the one inferred test command, so it runs (it logs `typescript test` to .calls.log) and is logged `assumed:` with package.json as its source. The bundled typescript commands (npx tsc, biome) never run, and the unrecorded build and lint keys read `skip (unresolved: ...)`. Nothing is installed. Needs --scaffold --allow-tools Bash."
tags: [toolchain, check, unattended, resolution-ladder, scaffold, no-network]
max_turns: 30
timeout_seconds: 600
allowed_tools: [Skill, Read, Glob, Grep, Bash]
expected_outcome: "npm test (or npm run test) runs the package.json test script and an `assumed: typescript.test-cmd=... (package.json:<line>)` line names it; no npx tsc, biome, eslint or install command runs; the build and lint cells read skip (unresolved: typescript.<key>) and Overall reads INCOMPLETE."
---

/toolchain:check --unattended
