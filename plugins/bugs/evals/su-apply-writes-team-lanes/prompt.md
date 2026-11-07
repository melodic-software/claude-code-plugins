---
description: "/bugs:setup apply on a committed repo with src/api/ and src/billing/ and no bugs config, where the user accepts every drafted lane up front: runs git probes before writing, writes only docs/conventions/bugs.yaml with lanes (kebab-case name plus globs on a real src/ directory) and no key outside the contract or filing_posture, re-reads it and runs git check-ignore on it after the write, recommends the .claude/**/*.local.* ignore line and says to commit the file. setup SKILL.md apply steps 2-7 and reference/config.md (Keys, lanes[] sub-keys, Consumer .gitignore). Needs --scaffold --allow-tools Bash Write Edit."
tags: [bugs, setup, apply, outcome, scaffold]
max_turns: 20
timeout_seconds: 480
allowed_tools: [Bash, Read, Glob, Grep, Write, Edit]
expected_outcome: "A git probe runs before the Write. docs/conventions/bugs.yaml holds lanes entries with name and globs (src/api/ or src/billing/), no other keys and no filing_posture. No other file is written or edited. After the write the file is re-read and git check-ignore confirms it is not ignored. The reply recommends .claude/**/*.local.* for the personal override and says to commit the new file."
---

/bugs:setup apply

Draft the lanes from this repository and accept each one you recommend: you do not need to ask me about them.
