---
description: "Scenario NM-script (near-miss stays quiet): fixing a bug inside an existing build script is close to tooling work but is an ordinary bug fix, so build-cli and audit-tools stay out of it. The source scenario checks that scripts/build.sh exits non-zero on a failed build; no grader can run a failing build, so build-fails-on-error reads scripts/build.sh for errexit set before `dotnet build`, or the build's status carried to the exit. The source scenario scores it pass/fail in the plugin arm only; the baseline arm should pass too"
tags: [stays-quiet, near-miss, scenario]
runs: 3
max_turns: 30
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Write, Edit, Bash, Skill]
expected_outcome: "scripts/build.sh exits non-zero when `dotnet build` fails, through set -e before the build, a `|| exit` on it, or a check of its status; docs/conventions/developer-experience.md is byte for byte as seeded; makes no Skill call to build-cli or audit-tools"
---

Fix a bug inside scripts/build.sh: it ignores a failed `dotnet build` and exits 0.
