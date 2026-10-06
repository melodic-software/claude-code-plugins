# Holdout acceptance tests

Detail behind the `### Holdout acceptance tests (opt-in)` section in [SKILL.md](../SKILL.md). The
option is off unless the plan's execution shape or the user turns it on for the run.

## Why it exists, and why it is opt-in

A worker that can see or edit the check that grades it can pass the check without meeting the
criterion. Three research groups observed frontier agents doing this (ImpossibleBench,
arXiv 2510.20270; METR, 2025-06-05; OpenAI, arXiv 2503.11926), on benchmark and training tasks
rather than production repositories, at rates that vary widely by task family. Anthropic's Claude
Code best-practices page offers one Claude writing tests and another writing code as an option.

The cost is measured in one study only. ImpossibleBench, on benchmark tasks, reports that hiding
tests during implementation cut cheating to near zero but also degraded legitimate performance,
while read-only tests kept performance and stopped test edits but not special-casing. The
read-only half is the default fence (SKILL.md, Dispatch cadence item 1.12). This file is the hidden
half, and it inherits the measured trade-off, so a plan turns it on where gaming is the bigger risk:
an unattended run, a phase whose acceptance criteria are executable, a behavior a worker could
special-case.

- **Pointer**: the test-writer split in
  [best practices](https://code.claude.com/docs/en/best-practices), the verification section.
- **As of**: 2026-10-06.
- **Recheck trigger**: that page drops or reframes the separate test writer, or a second study
  measures hidden tests' effect on legitimate performance.

## Steps

1. **Write before the phase's first wave.** The orchestrator writes the tests itself, or dispatches
   `implementation:implementer` as a test author under commit authority `orchestrator` with a
   brief whose ALLOWED set is the holdout directory alone. The author gets the phase's acceptance
   criteria, its design excerpt, and the public interfaces the plan names. It does not get the
   implementation, which does not exist yet, and its brief forbids reading the phase's worker
   worktrees. Each test names the criterion it checks.
2. **Store outside every fence.** Write them to `<memory_dir>/<slug>/holdout/phase-N/` in the
   orchestrator's checkout. The memory slice is self-ignored, so it is absent from a worker's
   dedicated worktree. Every worker brief lists that directory as FORBIDDEN to read and to write. A
   fence is an instruction, not a sandbox: a worker editing in the orchestrator's own checkout can
   still reach the slice, so the option is strongest when every worker edits in a dedicated
   worktree.
3. **Check the tests can fail.** Run them against the phase's base before dispatching. A holdout
   test that passes before the phase is built checks nothing new; rewrite it or drop it and log a
   `DEVIATIONS.md` discovery.
4. **Hand them to the verifier.** At the phase boundary the `phase-verifier` dispatch carries the
   holdout path, the exact run command, and the criterion each test maps to. When the runner
   accepts test paths outside the tree (most script-language runners), the command points at the
   holdout files with the worker's worktree as the working directory. When the ecosystem needs the
   tests inside the tree to build, the orchestrator creates a detached throwaway worktree at the
   phase head, copies the tests in, and hands that path instead. It never copies them into the
   worker's worktree.
5. **Feed back the criterion, not the test.** A holdout FAIL fails its criterion. The re-brief
   names the criterion and the observed behavior, never the test's source or its expected
   literals, which would turn the holdout into a visible target.
6. **When the holdout test is wrong.** A holdout test written from criteria alone can misread
   them. When the failure traces to the test rather than the code, the orchestrator fixes the test
   from the criteria, never from the code's output, and logs a `DEVIATIONS.md` entry. A disputed
   reading of a criterion is a human-decision entry, and Major divergence still stops the run.
7. **After `[DONE]`.** The tests may be promoted into the repository's suite in a test-only commit.
   From then on they are existing tests, read-only to later phases' workers under item 1.12.
