---
description: "The scaffold npm-installs a real markdownlint-cli2 0.24.0 into the workspace's node_modules/.bin. The run must probe PATH first and node_modules/.bin second, run the resolved binary with --help, and report PASS from the version banner on the first line of stdout although --help exits 2, installing and writing nothing. Needs --scaffold (npm and network for the install) --allow-tools Bash Write Edit (Write and Edit are granted so the must-not graders can fail). Run it with node on PATH and no markdownlint-cli2 on PATH. The run's home directory is temporary, so a mise shim for markdownlint-cli2 on PATH fails with 'not a valid shim'. If such a shim is on PATH, it resolves first, so the run never reaches the workspace copy. Pass --keep-temp to keep the trace that shows the --help probe running the real binary."
tags: [setup, prerequisites, outcome, scaffold]
runs: 3
max_turns: 15
timeout_seconds: 300
allowed_tools: [Skill, Read, Write, Edit, Glob, Grep, Bash]
expected_outcome: "Resolves markdownlint-cli2 at node_modules/.bin under the repository root after PATH holds none, runs it with --help, and reports a PASS row naming node_modules/.bin because the first line of stdout is the markdownlint-cli2 v0.24.0 version banner, even though --help exits 2. Runs no --version, no install command, and writes no file."
---

/docs-hygiene:setup
