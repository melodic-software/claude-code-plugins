# Mutation testing configuration

Read by `/mutation-testing:audit`, which the post-merge mutation lane
(`.github/workflows/post-merge-test-mutation.yml`) runs on every push to `main` that changes a
file in `mutate`. That workflow's trigger, `.github/workflows/post-merge-select-mutation-range.yml`,
lists the same globs as its `paths` filter; `.github/scripts/post-merge-test-mutation/report.test.mjs`
fails when the two lists differ.

Layers resolve user-global (`~/.claude/mutation-testing.md`) → team (this file) →
local overlay (`.claude/mutation-testing.local.md`). Scalars override; lists union. The lane
writes a local overlay with `diff-target` set to the push's previous head, so each run mutates
the lines that push changed.

```yaml
# No mutation tool drives every runner here (bash, node --test, pytest,
# vitest), so mutants are applied by the manual protocol in the principles
# skill's tooling.md.
tool: manual
command: none, the manual protocol applies each mutant by hand

# Mutants for one source file run against every suite scripts/affected-tests.sh
# selects for it, through one command, scripts/run-covering-tests.sh <file>;
# any failing suite kills the mutant.
diff-target: main

# Code the runners in scripts/run-test-file.sh can test. PowerShell is left
# out: that runner does not run Pester suites. .claude/ holds this config and
# the lane's overlay, which the model may not edit.
mutate:
  - "**/*.sh"
  - "**/*.mjs"
  - "**/*.js"
  - "**/*.ts"
  - "**/*.py"
  - "!**/*.test.*"
  - "!**/test_*.py"
  - "!**/conftest.py"
  - "!**/tests/**"
  - "!**/evals/**"
  - "!**/fixtures/**"
  - "!**/vendor/**"
  - "!.claude/**"

operators: default

# Measured 2026-10-25 on a Linux host: the covering suites of
# scripts/run-test-file.sh (4 suites) took 17,489 ms, of
# scripts/check-silent-revert.sh (10) 49,634 ms and of
# .github/scripts/pr-verify/resolve-pr.mjs (8) 72,571 ms. The slowest is
# the baseline; the timeout is 1.5 x that plus 5 s, rounded up.
baseline-suite-ms: 72571
timeout-ms: 115000

# The verify-pr route's profile caps the run at 60 turns. The audit spends
# about 17 on preflight, reading its references, baselines and triage, then
# about 4 per mutant (read, Edit, covering tests, git restore): 8 mutants is
# about 49 turns, and at about one covering-suite run each they fit the
# 60-minute job. A larger diff reports what it dropped.
max-mutants: 8
```

No `test-command`: the lane runs the default diff scope, and `scripts/run-test-file.sh` takes one
test file, so `audit --exercised` refuses here.
