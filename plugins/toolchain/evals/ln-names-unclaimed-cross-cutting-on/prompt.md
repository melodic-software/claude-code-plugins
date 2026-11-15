---
description: "The issue's demo: bare /toolchain:lint on a diff that changes a .rs file in a repository with no record for it, with cross-cutting opted in (a _typos.toml) as most repositories are. Markdown and cross-cutting checks log to .calls.log. The reply names src/lib.rs on the cross-cutting-only line, not on the Outside every ecosystem line, and the Overall line reads PASS. cross-cutting-ran reads .calls.log; rs-cross-cutting-only, rs-not-outside and overall-pass read the reply; meets-expectations (llm) judges the whole. Needs --scaffold --allow-tools Bash."
tags: [toolchain, lint, outcome, unclaimed-file, cross-cutting, scaffold, no-network]
max_turns: 25
timeout_seconds: 600
allowed_tools: [Skill, Read, Glob, Grep, Bash]
expected_outcome: "markdown check and cross-cutting check run; the reply names src/lib.rs as a changed file no ecosystem linter covers, only cross-cutting's text checks; it does not put src/lib.rs on an Outside every ecosystem line; the Overall line reads PASS."
---

/toolchain:lint
