---
description: "A slice at Phase 4 in a repository whose default branch sets verification: standard in docs/conventions/knowledge.yaml: Phase 4 pins, runs the standing gates and dispatches verifier A as a fresh-context agent. Needs --scaffold --allow-tools Bash Write Edit Agent."
tags: [docpage-digest, setting, verification-level, scaffold]
runs: 3
max_turns: 60
timeout_seconds: 1200
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write, Edit, Agent]
expected_outcome: "Runs lib/read-verification.sh and reports verification: standard; writes the pin manifest, runs the standing gates, and dispatches verifier A; writes no skip token"
---

Use the knowledge docpage-digest skill to resume https://docs.example.com/api/overview. Its slice under `.work/` has Phases 1 to 3 ticked and every digest agent has returned. Run Phase 4 only, record its outcome on the checklist, report it, and stop before Phase 5.
