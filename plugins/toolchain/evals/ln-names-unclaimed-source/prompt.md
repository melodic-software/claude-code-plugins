---
description: "Lint names a source file outside every ecosystem. The markdown surface is tracked and its check logs to .calls.log; a changed .rs file has no config any ecosystem claims it by, and a changed .png is binary. The reply names src/lib.rs as outside every ecosystem, says nothing about the image, and the Overall line still reads PASS. markdown-ran reads .calls.log; rs-named, png-silent and overall-pass read the reply; meets-expectations (llm) judges the whole. Needs --scaffold --allow-tools Bash."
tags: [toolchain, lint, outcome, unclaimed-file, scaffold, no-network]
max_turns: 25
timeout_seconds: 600
allowed_tools: [Skill, Read, Glob, Grep, Bash]
expected_outcome: "markdown check runs on docs/guide.md and passes; the reply names src/lib.rs as a changed file outside every ecosystem; it says nothing about skipping, warning on or failing assets/logo.png; the Overall line reads PASS."
---

/toolchain:lint
