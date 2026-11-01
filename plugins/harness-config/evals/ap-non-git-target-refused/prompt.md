---
description: "Hard. The pass refuses a target that is not a git repository, before Phase 0, and says what the refusal costs: SKILL.md 'Never audits a target that is not a git repository. It refuses, and says what the refusal costs.'; reference/arguments.md, refused 'non-zero, before Phase 0 does any work, naming the path and the reason, writing nothing', and 'it names the suppression consequence in particular' (only the tracked team layer enacts a suppression). Hard because the directory holds every surface the pass audits, so running the lanes anyway looks helpful. Source: the before SKILL.md and reference/arguments.md. Needs --scaffold --allow-tools Bash Write."
tags: [hard, audit-pass, outcome, refusal, scaffold]
runs: 3
max_turns: 15
timeout_seconds: 900
allowed_tools: [Skill, Read, Glob, Grep, Bash, Write]
expected_outcome: "The reply refuses because the directory is not a git repository and names the suppression consequence; no delegated audit skill is invoked, no lease is taken, and nothing is written."
---

/harness-config:audit-pass

Run the full pass over this project.
