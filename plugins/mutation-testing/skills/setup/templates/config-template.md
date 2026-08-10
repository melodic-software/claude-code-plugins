# Mutation testing configuration

Written by `/mutation-testing:setup apply`. Read by `/mutation-testing:audit`.

Layers resolve user-global (`~/.claude/mutation-testing.md`) → team (this file) →
local overlay (`.claude/mutation-testing.local.md`). Scalars override; lists union.
This file is team-shared and must be committed.

Arid-node suppressions live in a separate file, `.claude/mutation-testing-arid.md`,
so that a config diff reads as a policy change and a suppression diff reads as an
accepted finding.

```yaml
# The mutation tool driving this project's test runner.
# One of: stryker-js | stryker-net | stryker4s | pitest | infection | mutmut | manual
# `manual` means no off-the-shelf tool covers this language; the audit falls back
# to the single-operator manual protocol documented in the principles skill.
tool: <tool-id>

# How to invoke it. Left explicit rather than derived, because every project wraps
# its tooling differently (npm script, dotnet tool, gradle task, make target).
command: <exact command, e.g. "npx stryker run">

# The git ref the diff is taken against. Resolve it from the repository's own
# default branch -- `git symbolic-ref --short refs/remotes/origin/HEAD` -- and
# write the resolved value here. Never hardcode a branch name: this template is
# forge- and ecosystem-agnostic, and a repo whose trunk is not the one you assumed
# would silently scope every run to nothing.
diff-target: <resolved from origin/HEAD>

# Source roots to mutate. Exclude generated code, vendored directories, and test
# code -- mutating tests measures nothing.
mutate:
  - <glob>
  - <glob>

# Operator set. `default` means the tool's own defaults, which is the recommended
# value: optional and experimental operators raise the mutant count and the
# unproductive rate together.
# `narrow` restricts to statement-block removal plus relational-operator
# replacement, for a cheaper run on a slow suite.
operators: default

# Per-mutant timeout in milliseconds, derived from the measured baseline suite
# time recorded by `setup check` -- not guessed.
timeout-ms: <n>

# Measured wall-clock of one unmutated suite run, in milliseconds, at the time
# setup last ran. Recorded so the audit can report an estimated run cost before
# starting, and so a later slowdown is visible rather than inferred.
baseline-suite-ms: <n>

# Optional. Cap on how many mutants a single audit run will generate, as a guard
# against an unexpectedly large diff. Omit for no cap. When a run hits the cap it
# reports what it dropped -- a truncated run must never read as a clean one.
max-mutants: <n>
```

## Deliberately absent

**There is no score-threshold field.** A mutation score has a permanent, unknowable ceiling below
100% because equivalent mutants cannot all be removed, and every point of score is purchasable by
suppressing a mutant — so a gate selects for suppression over testing. Report the number; do not gate
on it. The reasoning, with sources, is in the `principles` skill's `scaling-and-suppression.md`.

## Notes for the reader of a diff

- A change to `mutate` changes what is measured — review it like a coverage-configuration change.
- A change to `operators` changes the denominator of every score. Scores before and after are not
  comparable.
- A change to `diff-target` can silently scope a run to nothing. Confirm it resolves.
