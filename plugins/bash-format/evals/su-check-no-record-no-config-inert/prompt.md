---
description: "check with no bash record, no .editorconfig and no .shellcheckrc. setup SKILL.md check step 4: the format row is none, INFO unresolved, the opt-out by design, while the lint row still resolves to ShellCheck on its defaults; the hooks run only the shfmt and ShellCheck adapters, and a bash record runs only through /toolchain:lint and /toolchain:check, written by /toolchain:setup apply bash. The file_exists graders catch a record or adapter config written. Needs --scaffold --allow-tools Bash Write Edit so the must-not graders can fail."
tags: [bash-format, setup, check, read-only, no-network]
max_turns: 14
timeout_seconds: 360
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write, Edit]
expected_outcome: "No record or config written, no Write or Edit. Format unresolved INFO and lint resolved to ShellCheck's defaults; not broken; the way forward is an .editorconfig shell section for the format hooks, or a bash record for /toolchain:lint."
---

/bash-format:setup check

Nothing gets formatted in this repo. Is bash-format broken?
