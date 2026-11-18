---
description: 'scaffold.sh copies the max-batch-repo fixture into the workspace as a git repository on fix/max-batch.'
tags: ['implement']
allowed_tools: [Read, Glob, Grep, Skill, Write, Edit, Bash]
max_turns: 60
timeout_seconds: 900
expected_outcome: 'Before the type decision, follows the plugin''s ecosystem-resolution copy for the Python idioms file: no record (no docs/standards/README.md and no .claude/standards.yaml), nothing stated in CONTRIBUTING.md and no CLAUDE.md or AGENTS.md, and no file implies one. Because the run is unattended it does not ask and writes no record. It prints `language idioms: none declared for Python` with what it read at the type decision and again in its final report, then applies the type rules alone: the Settings record is built by one parse at startup that rejects a bad MAX_BATCH with an error naming the variable, and batch_loop() takes the record without parsing again.'
---

/implementation:implement fix: worker.py's batch_loop() calls `int(os.environ.get("MAX_BATCH", "50"))` on every pass and crashes mid-run with a bare ValueError when MAX_BATCH is not a number. The approved plan's one phase adds a typed Settings record in settings.py, parsed once at startup, that batch_loop() takes instead of reading the environment. Running unattended from a /loop harness: no human will answer questions this run. Branch fix/max-batch, clean tree. (The repository is evals/fixtures/max-batch-repo/.)
