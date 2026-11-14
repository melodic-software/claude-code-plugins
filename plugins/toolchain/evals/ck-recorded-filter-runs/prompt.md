---
description: "Issue #16060 AC4. A recorded ecosystem id that no bundled default ships (zig, from a tracked .claude/ecosystems/zig.yaml) is covered, so naming it as the check filter runs its commands (they log `zig test` to .calls.log through tools/run.sh) instead of going to rung 3. ran-recorded-test reads .calls.log; not-uncovered reads the report. Needs --scaffold --allow-tools Bash."
tags: [toolchain, check, resolution-ladder, scaffold, no-network]
max_turns: 30
timeout_seconds: 600
allowed_tools: [Skill, Read, Glob, Grep, Bash]
expected_outcome: "The zig build, test and lint commands the tracked zig.yaml declares run (bash tools/run.sh zig ...); the report never says zig has no record."
---

/toolchain:check zig
