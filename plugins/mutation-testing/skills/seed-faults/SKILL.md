---
description: "Fault seeding: plants a few realistic defects one at a time in a throwaway worktree, runs the tests on each, and reports seeds caught over planted, each survivor's file:line, as an estimate. Nothing is committed. Use when: 'plant some bugs and see if the tests catch them', 'seed faults', 'how many realistic bugs would my suite catch', a check beyond generated mutants, or grading a reviewer on planted defects."
argument-hint: "--count <n> --paths <glob>... --tests <path>... --reviewer"
user-invocable: true
disable-model-invocation: false
metadata:
  workflow-stage: test
  summary: Plant hand-written defects in a throwaway worktree, report seeds caught over planted
---

# Seed faults

Plant a few realistic, hand-written defects, one at a time, and see which ones the tests catch.
Fault seeding is the older sibling of mutation analysis: a mutant comes from a fixed operator
catalog applied mechanically, a seed is a defect a person (here, an agent) would plausibly write,
such as a wrong boundary, a dropped error path, swapped arguments or a stale cache read. Where
`/mutation-testing:audit` asks whether each changed line is checked, this skill asks whether the
suite catches the kind of bug a developer actually ships.

## Arguments

- `--count <n>`: seeds to plant. Default 5. Keep it small: each seed costs one full run of the
  selected tests.
- `--paths <glob>...`: where seeds may go. Default: the configured `mutate` globs, else the
  production source files under the change on this branch.
- `--tests <path>...`: which test suites run against each seed. Default: the suites the configured
  `test-command` selects, with `{tests}` filled by the tests that cover the seeded paths.
- `--reviewer`: grade a fresh-context reviewer instead of the suite ([Grading a reviewer](#grading-a-reviewer)).

## The contract this skill holds

1. **Nothing planted reaches the repository.** Seeds live only in a throwaway worktree created
   outside the repository tree, never on a branch, never committed (not even inside the
   throwaway), and the worktree is removed on every exit path, failures included.
2. **What is graded never sees the seeds.** The planter may read the tests to make a seed
   realistic. The suite runs unchanged, and planted code carries no marker comment. The seed
   ledger (file, line, change, rationale) is kept outside the worktree, where neither the test run
   nor a graded reviewer can read it.
3. **The result is an estimate, not a defect count.** See [Reading the result](#reading-the-result).

## Phase 0: Preflight

1. **Config.** Resolve the config as `/mutation-testing:audit` does
   ([config and fallback](../audit/context/config-fallback.md)): the same layers, and the same rule
   that **the test command is never guessed**. With no `test-command` at any layer, ask for one or
   have the user confirm one you propose; an unattended run with no test command stops and asks.
2. **Snapshot.** Capture `git status --porcelain` and `git rev-parse HEAD` of the user's checkout.
   The run must end with both unchanged.
3. **Worktree.** `git worktree add --detach <dir> HEAD`, where `<dir>` is a fresh directory from
   `mktemp -d`, outside every repository tree (a copy inside the repository can be picked up by
   test discovery). Seeds go into `HEAD`: uncommitted edits in the user's checkout are not graded,
   and the scope report says so. Install what the tests need inside the worktree the way the
   project documents it.
4. **Baseline inside the worktree.** Run the selected tests there before any seed. A red baseline
   "catches" every seed and reports a perfect result, so a red baseline stops the run with its
   failure, after the worktree is removed.

## Phase 1: Plant (one ledger, outside the worktree)

Read the production code under the seed paths and the tests that cover it, then write the seed
ledger to a scratch file outside the worktree. Each seed is:

- **One realistic defect** a competent developer could commit: an off-by-one or wrong boundary, an
  inverted or dropped condition, a missing guard or error path, swapped arguments, a wrong default,
  a stale or wrong variable. Prefer defects the operator catalog in
  [operators-and-states.md](../principles/reference/operators-and-states.md) would not produce;
  a seed that is a one-token operator swap is a mutant, which `audit` already covers.
- **In a different function or branch** from every other seed, so one test cannot catch them all.
- **Behavior-changing.** Not a refactor, not dead code, not an equivalent change; if no input
  could tell the seeded program from the original, it is not a seed.
- **Code-only.** The planter reads tests and never edits them, and never edits test data or config.

Record per seed: id, `file:line`, the original text, the seeded text, and one line on the bug it
models. The ledger never enters the worktree.

## Phase 2: Run (one seed at a time)

Before the first seed, find from the repository and its toolchain every compiled or cached
artifact a test run can reuse instead of reading source: bytecode, incremental build output,
test-runner caches. A seed that keeps the file's size and lands in the same second as the last run
can otherwise run the cached build of the original code and read as `survived`.

For each seed: clear those artifacts in the worktree, or force a rebuild, then apply the seed, run
the selected tests, record the outcome, restore the file with `git -C <worktree> restore --
<file>`, and confirm `git -C <worktree> status --porcelain` is empty before the next seed. One seed
at a time is what lets a catch be attributed; seeds planted together cannot say which one a
failing test noticed.

| Outcome | Meaning |
|---|---|
| `caught` | At least one test failed or errored on a behavior assertion, or the run timed out |
| `survived` | Every selected test passed |
| `invalid` | The seed did not build or load, so the tests never judged it; counted apart, never as caught |

Replace an invalid seed with a new one once; if the replacement is invalid too, report both.

## Phase 3: Clean up and verify

`git worktree remove --force <dir>`, delete the ledger's scratch directory after the report is
drafted from it, then confirm three things before reporting: `git worktree list` no longer names
`<dir>`, and the user's checkout matches the Phase 0 snapshot in both `git status --porcelain` and
`git rev-parse HEAD`. A mismatch is the result: report it and stop, never a score over a changed
checkout.

## Phase 4: Report

```text
Seeds caught: <c> of <n> planted (estimate; <i> invalid, not counted)
Tests run per seed: <command>
Seeded at: <HEAD sha>; uncommitted edits not graded

| Seed | Location | Change | Bug it models | Outcome |
```

The reply always calls the ratio an estimate, beside the ratio, with the reason from
[Reading the result](#reading-the-result); a reply that drops the word reads as a defect count.
List every surviving seed with its `file:line`, the original and seeded text, and the behavior no
test checked. Then name the test that would have caught it; writing that test is
the job of `/testing:write` (if enabled), not this skill.

### Reading the result

Pezzè and Young, *Software Testing and Analysis: Process, Principles, and Techniques* (Wiley, 2008),
ch. 16 "Fault-Based Testing": "Fault seeding can be used to evaluate the thoroughness of a test
suite". Andrews, Briand and Labiche, "Is mutation an appropriate tool for testing experiments?",
Proceedings of the 27th International Conference on Software Engineering (ICSE 2005),
DOI 10.1145/1062455.1062530, found that mutants behave like real faults while hand-seeded
faults "seem to be harder to detect than real faults". So state the ratio as an estimate of thoroughness, likely a conservative one,
and never as a count of real defects; never extrapolate it into a number of defects remaining. A
small `--count` makes the estimate coarse: say so beside the ratio.

## Grading a reviewer

With `--reviewer`, plant every seed in the worktree at once, then dispatch one fresh-context
subagent with the seeded files (whole files, not a diff, since a diff of only seeds would name
them) and a neutral brief: review this code for defects and report each with `file:line`. The
brief never says faults were planted, how many, or where. A seed is caught when the reviewer
names its line or the line beside it and describes the same wrong behavior. Report caught over
planted the same way, then clean up as Phase 3 says.

## Why the agent plants the seeds

Our decision: seeding is agent-driven and tool-agnostic, so it works in any language with a test
command and needs no mutation tool installed.

## Next

- A seed survived and the killing test is due: `/testing:write`.
- Survivors on the changed lines themselves: `/mutation-testing:audit`.

## Gotchas

- **Seeds tuned to dodge the tests measure the planter, not the suite.** The planter reads the
  tests to make seeds realistic, not to hide them; a seed chosen only because no test reaches its
  line says the code is uncovered, which coverage already reports more cheaply.
- **A seed left by a crashed run is a planted bug.** Phase 3 runs on every exit path, and the
  snapshot check is what proves the user's checkout was never touched.
- **A run with every seed caught on a small `--count` is weak evidence.** Five of five says little
  about the sixth; report the count beside the ratio.

## What this skill does not do

- Commit, branch, or leave any seed in the user's checkout.
- Write or edit tests, test data, or config.
- Generate mutants with a tool or compute a mutation score: that is `/mutation-testing:audit`.
- Estimate how many real defects remain.
