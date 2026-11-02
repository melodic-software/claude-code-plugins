---
description: "setup apply downstream_probe=run, a value equal to the plugin default that the operator chose on purpose: the writer gets downstream_probe=run, never --default downstream_probe, and the new docs/conventions/review.yaml records downstream_probe as chosen (default run). Needs --scaffold --allow-tools Bash Write Edit."
tags: [review, setup, outcome, provenance, scaffold]
max_turns: 16
timeout_seconds: 600
allowed_tools: [Skill, Read, Glob, Grep, Bash, Write, Edit]
expected_outcome: "setup-apply.mjs runs with downstream_probe=run and never with --default downstream_probe; the written docs/conventions/review.yaml holds written_against: review@<version> and the provenance entry downstream_probe: chosen (default run), never downstream_probe: default."
---

/review:setup apply downstream_probe=run

The team chose run on purpose. Keep it run even if a later plugin version changes the default.
Leave every other setting unset. If setup asks about a convention home, skip that for now.
