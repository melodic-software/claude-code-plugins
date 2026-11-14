---
description: "Issue #16060 AC4. An unrecorded, unbundled ecosystem id that the repo's build files infer (rust, from a Cargo.toml) is covered when named as the lint filter: the inference pre-pass runs before the filter is checked, so the report names it on an `Inferred rust: globs ...` line and never says rust has no record. inferred-line and not-uncovered read the report. Needs --scaffold --allow-tools Bash."
tags: [toolchain, lint, resolution-ladder, scaffold, no-network]
max_turns: 30
timeout_seconds: 600
allowed_tools: [Skill, Read, Glob, Grep, Bash]
expected_outcome: "The report carries an `Inferred rust: globs ...` line naming a Rust glob; it never reports `rust: no record and nothing to infer it from`."
---

/toolchain:lint rust
