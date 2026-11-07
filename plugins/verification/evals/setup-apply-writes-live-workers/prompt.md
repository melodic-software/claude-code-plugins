---
description: 'Legacy setup 6. apply live_workers=3 with no file takes the value without asking, runs setup-apply.mjs with it, which creates docs/conventions/verification.yaml holding live_workers: 3 and no proof_level; then it re-runs the check row and reports the value read back and whether the file is tracked (setup SKILL.md apply steps 1, 2 and 5). runs-apply grades the call, file-live-workers and no-proof-level-key the written file, rereads-check a --check call, reports-tracked the tracked state in the reply, no-question no question; read-back-and-tracked (llm) legacy expectation 3 verbatim. Needs --scaffold --allow-tools Bash Write Edit.'
tags: [verification, setup, apply, scaffold, no-network, routine]
max_turns: 15
timeout_seconds: 480
allowed_tools: [Bash, Read, Glob, Grep, Write, Edit]
expected_outcome: 'Runs setup-apply.mjs live_workers=3, which writes docs/conventions/verification.yaml with live_workers: 3 and no proof_level; re-runs --check and reports live_workers: 3 read back, that /verification:confirm reads the default-branch copy, and that the file is untracked.'
---

/verification:setup apply live_workers=3

The repository has no docs/conventions/verification.yaml yet.
