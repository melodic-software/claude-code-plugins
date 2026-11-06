---
description: "A repository whose default branch sets verification: light in docs/conventions/playwright.yaml, with a rendered demo whose quality control passed: demo-video step 8 reads the level, dispatches no independent frame review, writes the skip token and posts nothing. Needs --scaffold --allow-tools Bash and a sandbox backend. Host tool: git for the scaffold."
tags: [playwright, demo-video, setting, verification-level, scaffold]
runs: 3
max_turns: 25
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Skill, Bash, Agent]
expected_outcome: "Runs lib/read-verification.sh and reports verification: light; dispatches no subagent; writes verification: skipped (light); does not post the video."
---

Use the playwright demo-video skill. ./work/demo.mp4 is rendered and quality_control.py passed (./work/quality-control/quality-control.json). Do step 8 and then step 9 to post it to pull request 12.
