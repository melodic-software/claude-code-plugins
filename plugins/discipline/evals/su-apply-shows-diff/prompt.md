---
description: "Legacy setup 5, without its narration: the scaffold's repository tracks docs/conventions/discipline.yaml holding lever_scope: non-trivial under a comment line. setup-apply.mjs exits 3 with a unified diff and writes nothing; the skill shows the diff and asks, and the apply request is not the yes (SKILL.md lines 160-163). shows-diff needs the - non-trivial and + deterministic lines, asks-confirm a question about writing it, no-yes and no-decline forbid the --yes and --decline re-runs, no-shell-write a shell write to the file, file-unchanged the file's contents after the run exactly as seeded, comment included (a { source: file } target reads the workspace file after the run, scaffold-created or not). Needs --scaffold and --allow-tools Bash, with a real node first on PATH."
tags: [discipline, setup, outcome, scaffold, no-network]
max_turns: 15
timeout_seconds: 400
allowed_tools: [Skill, Read, Glob, Grep, Bash]
expected_outcome: "Runs setup-apply.mjs lever_scope=deterministic (exit 3), shows the diff from non-trivial to deterministic, asks whether to write it, and never re-runs with --yes."
---

/discipline:setup apply lever_scope=deterministic
