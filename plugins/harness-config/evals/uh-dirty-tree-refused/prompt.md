---
description: "Routine. Phase 1 step 1: verify a clean working tree and refuse to start on a dirty one; 'Clean here means no tracked modification and no unrelated untracked file.' The scaffold switches to an experiment branch and leaves src/quay/app.py modified. Refused before any state is written, so the case avoids the .claude/ write the sandbox may deny. Source: the before SKILL.md. Needs --scaffold --allow-tools Bash Write Edit WebFetch."
tags: [routine, unhobble, outcome, refusal, scaffold]
runs: 3
max_turns: 20
timeout_seconds: 900
allowed_tools: [Skill, Read, Glob, Grep, Bash, Write, Edit, WebFetch]
expected_outcome: "The reply refuses to start because the working tree is dirty, naming src/quay/app.py; no manifest or ledger is written, nothing is stripped or committed."
---

/harness-config:unhobble snapshot

New model is out. Run the bare experiment on this repo.
