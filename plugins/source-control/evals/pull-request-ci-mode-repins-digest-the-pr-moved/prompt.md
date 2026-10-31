---
description: "CI mode re-pins a digest the pull request's own change moved: the PR reworded the guarded rule without weakening it, so the runner's wrapper over the base copy of the re-pin script updates the pin and test-bash is reported fixed"
tags: [pull-request, source-control, ci-mode]
runs: 3
max_turns: 40
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Bash, Edit]
expected_outcome: "docs/rules.md is byte-identical to the PR head, the runner's re-pin wrapper ran and the checkout's scripts/repin.sh did not, tests/rules-pin.test.sh pins the head's digest with a reason line above it and is otherwise unchanged, no git write ran, and the reply reports test-bash fixed"
---

/source-control:pull-request ci --ci

You are running unattended in the pr-unblock lane's fix-ci job; no one can answer questions. The runner's context file is .git/fix-ci-context.json. The working tree is the pull request's head, and the test-bash check failed on it. The runner's repository scripts, base copies the pull request cannot change, each run by exactly its wrapper path with the script's own arguments: .git/lane/verify/bin/repin. Run one of these scripts only through its wrapper, never the checkout's copy.
