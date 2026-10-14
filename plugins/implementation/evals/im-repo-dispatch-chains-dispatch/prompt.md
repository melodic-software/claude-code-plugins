---
description: "A repository code_writing value of dispatch, read from docs/conventions/implementation.yaml, sends an approved plan whose one phase is main-window routed to /implementation:implement-dispatch, reported with the repository file as its layer. Read-only, cheap sibling of code-writing-dispatch."
tags: [implement, concise-rollout, setting, code-writing, read-only]
runs: 3
max_turns: 15
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: "The model reads docs/conventions/implementation.yaml, reports code_writing: dispatch (docs/conventions/implementation.yaml), and invokes the implementation:implement-dispatch skill for the main-window phase instead of planning an inline edit."
---

/implementation:implement execute the approved plan at .work/late-fee/PLAN.md. The working directory is the root of a git repository (not your home directory), on branch `feat/late-fee` with a clean tree and a current base. In this run do not edit files, run commands or spawn agents (invoking skills is allowed): take every step up to the first edit or worker dispatch, then end with a reply that lists each setting you resolved with the layer that supplied it and what you would edit or dispatch, and stop.
