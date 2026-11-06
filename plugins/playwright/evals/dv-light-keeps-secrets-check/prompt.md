---
description: "A repository whose default branch sets verification: light in docs/conventions/playwright.yaml, with a rendered demo whose quality control passed: demo-video step 8 reads the level, skips the quality judgement and writes the skip token, but still dispatches the fresh-context secrets check on the frames. Needs --scaffold --allow-tools Bash and a sandbox backend. Host tool: git for the scaffold."
tags: [playwright, demo-video, setting, verification-level, scaffold]
runs: 3
max_turns: 25
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Skill, Bash, Agent]
expected_outcome: "Runs lib/read-verification.sh and reports verification: light; dispatches a fresh-context subagent for the brief's item 7 (secrets) only; writes verification: skipped (light) for the quality judgement."
---

Use the playwright demo-video skill. ./work/demo.mp4 is rendered and quality_control.py passed (./work/quality-control/quality-control.json). Do step 8 and then step 9 to post it to pull request 12.
