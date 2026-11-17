---
description: "establish-hub apply on a hub with no resolvable repository-listing command reports the repository map unresolved, leaves its pointer out and writes no list of repositories, even with two sibling checkouts in sight"
tags: [establish-hub, apply, repository-map, scaffold, no-network]
runs: 3
max_turns: 40
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write, Edit]
expected_outcome: "The reply reports the repository map unresolved. AGENTS.md is written without a list of repositories: it names neither ledger-service nor portal-web and holds no guessed forge listing command."
---

/instruction-placement:establish-hub apply

I am answering the interview up front, so do not ask me anything.

- The hub spans no other owner or account than the one in its remote.
- I keep no machine-wide instructions; leave that out.
- Scratch files go in `.work/`.
- Cross-repository decisions are recorded nowhere yet; leave that section out.
- I do not know of any command that lists our repositories, and none is set up here.

I say yes to each change you show me for `AGENTS.md`, for the `CLAUDE.md` shim and for the `.gitignore` line, and I want every other section of the hub's `AGENTS.md` you can fill from what you find.
