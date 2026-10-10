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
   orchestrator's checkout. The memory slice is self-ignored, so a worker's dedicated worktree
   holds no copy of it. That is not isolation: a worker runs as the same user on the same
   filesystem and can read the slice by absolute path. Every worker brief lists the whole
   memory-slice root as FORBIDDEN to read and to write, and never names the holdout path, which
   would tell the worker where to look. A fence is an instruction, not a sandbox, so the option
   raises the cost of gaming the check rather than ruling it out, and it is weaker still when a
   worker edits in the orchestrator's own checkout.
3. **Check the tests can fail.** Run them against the phase's base before dispatching, with the
   pinned command step 4 describes. A holdout test that passes before the phase is built checks
   nothing new; rewrite it or drop it and log a `DEVIATIONS.md` discovery.

   Then show the user one plain-language line per test, what it asserts and which criterion it
   checks, and keep only the tests they approve; in a run with no user present, record that list
   in `DEVIATIONS.md` for review at PR time. Record a hash of every file in the phase's holdout
   directory, nested and dot files included
   (`find <holdout>/phase-N -type f -print0 | sort -z | xargs -0 sha256sum`), in the
   orchestrator's notes. The directory holds regular files and directories only: an entry of any
   other type, such as a symlink (`find <holdout>/phase-N ! -type f ! -type d` prints it), fails
   the recheck.

   **Optional lock.** When the plan or the user opts in, launch each worker that runs as its own
   `claude` session with the deny rules `Read(//<memory-slice root>/**)` and
   `Edit(//<memory-slice root>/**)`, through `--disallowedTools` or a `--settings` file outside the
   worker's worktree. The root, not the holdout path, keeps the rule from pointing at the tests. A
   worker dispatched as a subagent of the orchestrator's session gets no such rule: a session-wide
   deny would also stop the orchestrator, which reads and writes the slice, and a subagent's
   `disallowedTools` removes a whole tool rather than one path. The rules stop Claude's file tools
   and the shell file commands Claude Code recognizes, not a script that reads or writes files
   itself (`python -c`, `node -e`), so the hash recheck in step 4 stays the gate.

   - **Pointer**: [Read and Edit](https://code.claude.com/docs/en/permissions#read-and-edit) in
     the permissions page, for the path syntax and what a deny does not cover.
   - **As of**: 2026-10-10.
   - **Recheck trigger**: that section changes `//` path anchoring or starts covering files a
     script opens itself, or subagent definitions gain path-scoped deny rules.
4. **Hand them to the verifier in a throwaway worktree.** At the phase boundary the orchestrator
   first rechecks the step 3 hash; a change it did not make itself (step 6, which records a new
   hash) is a Major divergence and stops the run. It then creates a detached throwaway worktree at
   the phase head, never reusing a worker's worktree, and the `phase-verifier` dispatch carries
   that path, the holdout path, the exact run command, and the criterion each test maps to. When
   the ecosystem needs the tests inside the tree to build, the orchestrator copies them into the
   throwaway worktree, never into a worker's. It removes the throwaway worktree after the verdict.

   The phase diff is worker-authored, and a test runner executes configuration it finds in the
   tree: a new `conftest.py` hook can force a pass, a pytest ini can add options, a `pretest`
   script runs before the tests, a Jest or Vitest config can name setup files. So the run command
   takes its configuration from the holdout directory and invokes the runner binary directly,
   never through a package script. For example, `pytest --noconftest -c <holdout>/pytest.ini
   --rootdir <holdout> -p no:cacheprovider`, `vitest run --config <holdout>/vitest.config.ts`, or
   `jest --config <holdout>/jest.config.js`. A runner configuration or test setup file the phase
   diff adds or changes is a verifier finding (SKILL.md, Dispatch cadence item 1.12).

   - **Pointer**: the runners' own flag references:
     [pytest command-line flags](https://docs.pytest.org/en/stable/reference/reference.html#command-line-flags),
     [Vitest CLI](https://vitest.dev/guide/cli),
     [Jest CLI](https://jestjs.io/docs/cli).
   - **As of**: 2026-10-06.
   - **Recheck trigger**: a runner renames or drops a flag above, or starts loading configuration
     or setup files from the tree despite an explicit config path.

5. **Feed back the criterion, not the test.** A holdout FAIL fails its criterion. The re-brief
   names the criterion and the observed behavior, never the test's source or its expected
   literals, which would turn the holdout into a visible target.
6. **When the holdout test is wrong.** A holdout test written from criteria alone can misread
   them. When the failure traces to the test rather than the code, the orchestrator fixes the test
   from the criteria, never from the code's output, records its new hash, and logs a
   `DEVIATIONS.md` entry. A disputed reading of a criterion is a human-decision entry, and Major
   divergence still stops the run.
7. **After `[DONE]`.** The tests may be promoted into the repository's suite in a test-only commit.
   From then on they are existing tests, read-only to later phases' workers under item 1.12.
