---
description: "Fixture check: the shared seed builds all seven fixture states, read back through the conventions file each copy's AGENTS.md names. It measures the fixtures, not the plugin, so both arms should pass"
tags: [fixtures]
runs: 1
max_turns: 20
allowed_tools: [Read, Glob, Grep]
expected_outcome: "Names docs/conventions/developer-experience.md for both converged copies, .claude/developer-experience.md for tarnquill-legacy, and none for the bare and conventions-only copies"
---

Each top-level directory in this workspace is a copy of a repository. For each directory, read its AGENTS.md and reply with one line in the form `<directory>: <path>`, where `<path>` is the file that AGENTS.md says to read before changing developer tools, or `none` when it names no such file. Reply with those lines only.
