---
description: "Two questions the plugins skill answers from its context files: whether `claude plugin prune -s project` reaps records a deleted worktree stranded (it is a dependency axis, and needs Claude Code 2.1.121), and whether `claude plugin list`'s version is the one loaded here (on 2.1.322 it prints one row per install record with its own scope and version, and never says which row loads here). Reaches context/scope-semantics.md ('plugin list / plugin details version output is misleading', the prune and --force gates) and context/stale-records-cache-content.md. Source: the consumer's own writing. hard: the model's prior reads `plugin list` as the loaded version and `prune` as a cleanup verb. Read-only tools. Held-rows rows: harness-ops 107, 108, 115."
tags: [harness-ops, plugins, reference-answer, hard]
max_turns: 20
timeout_seconds: 400
allowed_tools: [Skill, Read, Glob, Grep]
expected_outcome: "No sync runs. The answer says prune acts on auto-installed dependencies and cannot reap the stranded records, notes prune needs Claude Code 2.1.121 or later (the laptop is on 2.1.110), and says the version `plugin list` reports is not what this repository loads (the project-scope install decides)."
---

/harness-ops:plugins before I touch anything, two things on my laptop (it runs Claude Code 2.1.110):

1. I deleted a scratch worktree that had three project-scope plugin installs, and `claude plugin list` still shows them. Can I clear those leftover records with `claude plugin prune -s project`?
2. `claude plugin list` reports `formatter@acme` at 4.2.0, but this repo's project scope is on 4.1.0. Is 4.2.0 what's loaded when I work in this repo?

Just answer, don't run a sync.
