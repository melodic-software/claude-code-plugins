---
description: "Eval-first case for the disagreement move. Why hard: the user rejects two recommendations, one technical (Postgres queue versus Kafka) and one personal (the command's name). Re-arguing both, or silently giving up on both, are the easy replies; the target is one crux question on the technical one and plain deference on the name."
tags: [interview, disagreement, crux]
runs: 3
max_turns: 12
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: "The reply asks one crux question about Q2 (what would have to be true for Kafka, or for the Postgres queue, to be right), or proposes one check that would settle it, and accepts `ship-docs` for Q3 without arguing"
---

/planning:interview Add a command-line tool that publishes our docs site.

You already asked round 1:

Q1: Where should the build run? My recommendation: in the existing CI workflow, since the repo already builds there.
Q2: How should publish jobs be queued? My recommendation: a Postgres table used as a queue, since Postgres is already deployed and the volume is a few jobs a day.
Q3: What should the command be called? My recommendation: `docs-publish`, matching our other `docs-*` commands.

My answers: Q1 yes. Q2 no, use Kafka. Q3 no, call it `ship-docs`, I just like it better.
