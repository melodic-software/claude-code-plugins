---
description: "Hard retrieval (version-changed fact): locate a default compression algorithm and CLI flag that changed in a prior major release despite stale top-level docs"
tags: [routing, retrieval, hard]
max_turns: 30
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep]
expected_outcome: "default_compression: zstd; override_flag: --codec; changed_in_version: 3.0.0."
---

The current directory holds documentation and release files for the `packctl` CLI tool. Answer from its files.

For the current release of `packctl`, what is the default archive compression algorithm used by `packctl bundle`, what CLI flag overrides it, and which version introduced that change? Reply in three lines:

default_compression: <algorithm>
override_flag: <flag>
changed_in_version: <semver>
