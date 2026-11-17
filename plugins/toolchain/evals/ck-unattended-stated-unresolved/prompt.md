---
description: "Unattended, with no record: the command CLAUDE.md states runs (it logs `bash check scripts/app.sh` to .calls.log) and is logged `assumed:` with CLAUDE.md as its source; markdown, which nothing states or implies, reads `skip (unresolved: markdown.check-cmd)`, no bundled markdownlint runs, and the run is INCOMPLETE. Nothing is written, edited, recorded or installed. Needs --scaffold --allow-tools Bash."
tags: [toolchain, check, unattended, resolution-ladder, scaffold, no-network]
max_turns: 30
timeout_seconds: 600
allowed_tools: [Skill, Read, Glob, Grep, Bash]
expected_outcome: "The stated `bash tools/run.sh bash check scripts/app.sh` runs and an `assumed: bash.check-cmd=... (CLAUDE.md:<line>)` line names it; the markdown row's lint cell reads skip (unresolved: markdown.check-cmd); Overall reads INCOMPLETE; no markdownlint, install, Write, Edit or write into .claude/ecosystems/ happens."
---

/toolchain:check --unattended
