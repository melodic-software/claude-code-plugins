---
description: "--fix runs only the format-only fix-cmd; the semantic code-fix-cmd never runs under it"
tags: [toolchain, lint, outcome, fix]
max_turns: 25
timeout_seconds: 600
allowed_tools: [Skill, Read, Glob, Grep, Bash]
expected_outcome: "tools/format.sh runs on app.sh, so app.sh gains a '# format: applied' line and loses its trailing whitespace; tools/semantic-fix.sh never runs, so app.sh still calls legacy_greeting twice and has no 'code-fix applied' line."
---

/toolchain:lint --fix
