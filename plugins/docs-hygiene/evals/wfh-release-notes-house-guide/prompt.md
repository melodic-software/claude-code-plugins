---
description: "Hard case. Why hard: the project has no STYLE.md; its release-note rules (heading names and order, which commits to leave out) live in docs/contributing/writing.md, linked from CONTRIBUTING.md. The contract resolves the project guide before any default and names it; a no-skill run falls back to Keep a Changelog headings and lists internal commits. Written from the before SKILL.md contract"
tags: [write-for-humans, release-notes, house-style, hard]
runs: 3
max_turns: 12
timeout_seconds: 400
allowed_tools: [Skill, Read, Glob, Grep]
expected_outcome: "The notes use the house headings Breaking changes, New, Fixed in that order, put the --out-dir to --output rename under Breaking changes, leave out the ci, test, refactor, dependency and docs commits, and the reply names docs/contributing/writing.md as the guide applied"
---

We're cutting tallyctl 2.4.0. Write the release notes from the commits since 2.3.0 below. Reply with the notes in one ````markdown fenced block (four backticks).

```text
a1f3c9e feat(export): add --format parquet to tallyctl export
9b2d417 fix(sync): stop tallyctl sync hanging when the remote returns 304
4c8e0aa feat(export)!: rename --out-dir to --output on tallyctl export (old flag removed)
e7d51f2 ci: pin actions/checkout to v4.2.2
0fa93bc test: deflake the sync retry test
5d6c2e1 refactor(core): split ledger.rs into ledger/mod.rs and ledger/io.rs
b88a0d4 chore(deps): bump serde from 1.0.210 to 1.0.214
13e7f9c docs: fix typo in README
2a9c4d8 fix(import): tallyctl import no longer drops the last row of a CSV without a trailing newline
```
