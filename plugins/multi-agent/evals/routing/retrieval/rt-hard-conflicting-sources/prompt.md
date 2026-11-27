---
description: "Hard retrieval (conflicting sources): weigh multiple conflicting docs and configs to find the authoritative webhook retry backoff cap and jitter mode"
tags: [routing, retrieval, hard]
max_turns: 30
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep]
expected_outcome: "authoritative_source: docs/contracts/webhook-delivery.md; max_backoff_seconds: 90; jitter_mode: decorrelated."
---

The current directory holds documentation and configuration files for the `ledger-sync` service. Answer from its files.

Several files in this repository describe webhook delivery retry settings and disagree with one another. Determine which file is the authoritative source of truth today, and report the effective maximum retry backoff in seconds and the jitter mode it requires. Reply in three lines:

authoritative_source: <path from the current directory>
max_backoff_seconds: <integer>
jitter_mode: <strategy>
