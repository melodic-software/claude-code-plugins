---
description: "establish-hub apply, with every answer given up front, writes only the accepted sections into the hub's AGENTS.md, the one-line CLAUDE.md shim and the scratch .gitignore line, leaves the declined decisions section unwritten, writes no list of repositories, and leaves the sibling repository's checkout unchanged"
tags: [establish-hub, apply, operator-gate, scaffold, no-network]
runs: 3
max_turns: 40
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write, Edit]
expected_outcome: "AGENTS.md exists and holds the start-here, what-belongs-where, where-work-is-filed, dispatching and working-material sections; it holds nothing on where cross-repository decisions live and no list of repositories. CLAUDE.md is exactly @AGENTS.md, .gitignore ignores .work/, and ledger-service/AGENTS.md is untouched with no ledger-service/CLAUDE.md created."
---

/instruction-placement:establish-hub apply

I am answering the interview up front, so do not ask me anything.

- The hub spans no other owner or account than the one in its remote.
- I keep no machine-wide instructions; leave that out.
- Scratch files go in `.work/`.

I say yes to each of these changes, and to nothing beyond them:

- `AGENTS.md` in this repository with the sections on how a session starts here, what belongs where, where work is filed, how work is dispatched to a repository, and working material.
- `CLAUDE.md` as the one-line `@AGENTS.md` shim.
- A `.work/` line in `.gitignore`.

I say no to the section on where cross-repository decisions live: do not write it.
