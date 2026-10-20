---
description: "A vertical slice that fits one fresh context window is also checked for integrating at least daily, with no hours estimate"
tags: [decompose, slice-size]
runs: 3
max_turns: 20
timeout_seconds: 300
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: "Applies the window bar to the draft slice, finds it fits one fresh context window, also states it can merge to the mainline at least daily, and gives no hours estimate or day cap"
---

Load /work-items:decompose and apply its four checks to this draft vertical slice. Report one line per
check, then say what to do with the slice.

Draft slice: "Add a `--month` flag to the refund export command, with the config key it reads, the
code path that honors it, and a test that runs the command for one month." It touches three files and
needs no other slice to run.
