---
description: 'Legacy setup 7. apply live_workers=0 over a file holding live_workers: 2: the script refuses with one line (not a whole number of at least 1), exits 1 and writes nothing; the skill reports that, leaves the file at 2, and neither substitutes another value nor passes --yes (setup SKILL.md apply step 2). runs-apply grades the call, no-yes no --yes, file-unchanged the file still at live_workers: 2, names-minimum the rule in the reply; no-substitute (llm) legacy expectations 1 and 3 verbatim. Needs --scaffold --allow-tools Bash Write Edit.'
tags: [verification, setup, apply, refusal, scaffold, no-network, routine]
max_turns: 12
timeout_seconds: 480
allowed_tools: [Bash, Read, Glob, Grep, Write, Edit]
expected_outcome: 'Runs setup-apply.mjs live_workers=0, reports the refusal (not a whole number of at least 1), and leaves docs/conventions/verification.yaml at live_workers: 2.'
---

/verification:setup apply live_workers=0

The repository already has docs/conventions/verification.yaml with `live_workers: 2`.
