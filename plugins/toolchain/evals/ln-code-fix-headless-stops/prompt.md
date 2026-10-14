---
description: "Headless --code-fix without --yes emits the plan and stops: nothing is mutated and the reply says to re-run with --yes"
tags: [toolchain, lint, outcome, code-fix, consent]
max_turns: 25
timeout_seconds: 600
allowed_tools: [Skill, Read, Glob, Grep, Bash]
expected_outcome: "The reply shows the code-fix plan naming the command (tools/semantic-fix.sh) and the scoped file app.sh, applies nothing (app.sh still calls legacy_greeting twice and has no 'code-fix applied' line; tools/semantic-fix.sh is never executed), and tells the operator to re-run with --yes to apply."
---

/toolchain:lint --code-fix
