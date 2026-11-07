---
description: 'Legacy setup 4. apply proof_level=strict over an existing proof_level: path runs setup-apply.mjs, which exits 3 and prints a unified diff; the skill shows it and waits for an explicit yes, never passing --yes on its own, and before recommending strict says an older release does not read the file (setup SKILL.md apply steps 1 and 3). runs-apply grades the call, no-yes no --yes, file-unchanged the file still holding proof_level: path, shows-diff the diff in the reply; waits-for-yes (llm) legacy expectation 1 verbatim. Expectations 2 and 3 (the read-back value and when the level applies, after the write) are held: no one answers the yes in a run. Needs --scaffold --allow-tools Bash Write Edit.'
tags: [verification, setup, apply, scaffold, no-network, routine]
max_turns: 15
timeout_seconds: 480
allowed_tools: [Bash, Read, Glob, Grep, Write, Edit]
expected_outcome: 'Runs setup-apply.mjs proof_level=strict, shows the -proof_level: path / +proof_level: strict diff, asks for an explicit yes, notes older releases do not read the file, and leaves the file unchanged.'
---

/verification:setup apply proof_level=strict

The repository already has docs/conventions/verification.yaml with `proof_level: path`.
