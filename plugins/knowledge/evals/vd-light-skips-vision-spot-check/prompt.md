---
description: "A repository whose default branch sets verification: light in docs/conventions/knowledge.yaml, with a slice seeded at Phase 9: the 9.4 vision fidelity spot-check (context/quality-gates.md, Structural vs vision fidelity) reads the level, dispatches no fresh-context subagent, writes the skip token, and reports the slice structural complete only rather than spot-checking its own images. Needs --scaffold --allow-tools Bash and a sandbox backend. Host tools: git and ffmpeg for the scaffold."
tags: [knowledge, video-digest, setting, verification-level, scaffold]
runs: 3
max_turns: 20
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Skill, Bash, Agent]
expected_outcome: "Runs lib/read-verification.sh and reports verification: light; dispatches no subagent; writes verification: skipped (light); calls the slice structural complete, not vision-complete."
---

Use the knowledge video-digest skill. My watch slice in ./slice is at Phase 9: 9.1 and 9.2 passed. Do checklist item 9.4, the vision fidelity spot-check, and tell me whether the slice is vision-complete. Do not close the slice.
