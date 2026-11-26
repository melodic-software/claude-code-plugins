---
description: "/bugs:setup apply on a committed repo with src/api/ and src/billing/ and no bugs config, where the user accepts every drafted focus area up front: runs git probes before writing (Write tool or a shell write), writes only docs/conventions/bugs.yaml with focus areas (kebab-case name plus globs on a real src/ directory) and no key outside the contract or filing_posture, re-reads it and runs git check-ignore on it after the write (a later call or later in the writing command), recommends the docs/conventions/**/*.local.* ignore line and says to commit the file. setup SKILL.md apply steps 2-7 and reference/config.md (Keys, focus areas[] sub-keys, Consumer .gitignore). Needs --scaffold --allow-tools Bash Write Edit."
tags: [bugs, setup, apply, outcome, scaffold]
max_turns: 20
timeout_seconds: 480
allowed_tools: [Bash, Read, Glob, Grep, Write, Edit]
expected_outcome: "A git probe runs before docs/conventions/bugs.yaml is first written, by the Write tool or a shell write. docs/conventions/bugs.yaml holds focus area entries with name and globs (src/api/ or src/billing/), no other keys and no filing_posture. No other file is written or edited. After the write (in a later call or later in the same command) the file is re-read and git check-ignore confirms it is not ignored. The reply recommends docs/conventions/**/*.local.* for the personal override and says to commit the new file."
---

/bugs:setup apply

Draft the focus areas from this repository and accept each one you recommend: you do not need to ask me about them.
