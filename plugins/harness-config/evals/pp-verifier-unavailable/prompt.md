---
description: "Hard. When dispatch is unavailable: Phase D requires a fresh-context verifier; with no Agent tool the report header discloses that Phase D did not run and why, and every unverified proposal carries an (unverified) marker. The case grants no Agent tool. purge-builds guarantees at least one proposal. Hard because skipping the disclosure leaves a report that reads as verified. At risk in the sandbox: Phase D persists last-audit.md under ${CLAUDE_PLUGIN_DATA}, which the sandbox denied on slice A; graders read the chat report and tool calls only. Needs network: Phase A aborts when the best-practices page cannot be fetched. Needs --scaffold --allow-tools Bash Write WebFetch. Run it in a pass of its own with --disallow-tools Agent, in every pass: an --allow-tools grant applies to every case in the run, so a shared pass that grants Agent gives this case the verifier it is built to lack."
tags: [hard, audit-prompting-postures, outcome, verifier-disclosure, scaffold, plugin-data-risk, own-pass-no-agent]
runs: 3
max_turns: 30
timeout_seconds: 1800
allowed_tools: [Skill, Read, Glob, Grep, Bash, Write, WebFetch]
expected_outcome: "The best-practices guide is fetched; the reply says Phase D did not run because no subagent could be dispatched, marks each proposal (unverified), and writes no skill file."
---

/harness-config:audit-prompting-postures skills

Quick posture check on our skills, please.
