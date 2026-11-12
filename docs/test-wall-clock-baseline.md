# Test wall-clock baseline

Per-suite and per-gate wall clock on the Linux CI runner and on a Windows Git
Bash host, side by side, so a change to the test tooling can be measured
against both. The selector that decides which suites a change runs is
`scripts/affected-tests.sh`; the runner that times them is
`scripts/run-plugin-tests.sh`.

## Producing each column

Both tools write the same tab-separated rows: the path, its wall seconds and
its exit code.

### Shell suites

`bash scripts/run-plugin-tests.sh --timings <file> [<suite> ...]` writes one
row per suite after the run. With no suite argument it runs the whole shell
corpus; a suite argument is a repo-relative path. Seconds are whole, the same
number the `TIME: <suite> <n>s` line prints.

- **Linux CI.** Every `test-bash (<n>)` job of a whole-tree `pr-require-checks`
  run on main prints a `TIME:` line per suite. Read each job's log with
  `gh run view --log --job <job-id>` and keep its `TIME:` lines; the legs
  together cover the shell corpus. The log read needs an authenticated `gh`.
- **Windows Git Bash.** Run
  `bash scripts/run-plugin-tests.sh --timings <file>` from the repository root
  in Git Bash, at the default `--jobs 1`.

### Gate scripts

`bash scripts/time-gates.sh --timings <file> [--base <ref>]` runs each gate
below once, from the repository root, and writes its row. `--base` defaults to
`origin/main`. Seconds carry milliseconds, since a gate can finish in under a
second on Linux. A gate that fails on the tree still gets its time and exit
code.

## Windows host

The Windows Git Bash numbers come from one host on 2026-11-04: Windows 11
build 10.0.26300.9711, MSYS `3.6.10`, GNU bash 5.3.15, Git for Windows
2.56.0.windows.4, 24 logical processors, on a native `C:` clone of `origin/main`
at `284b5303ae65`. Fifty `bash -c true` launches took 1.859 s, 37.2 ms each,
so the host does not carry the #3715 process-creation condition. The WSL 1-minute
load on the same machine stayed under 3 throughout.

- **Full corpus.** Not finished in 60 minutes. A `--jobs 1` run of the
  `fd862a49b848` tree under a 3600 s `PLUGIN_TEST_DEADLINE` stopped after
  3716 s with 18 of 829 suites done (3647 suite-seconds) and 811 never
  started. The 829 is the count `origin/main`'s runner at `284b5303ae65`
  discovered in that tree under `--root`, against the 820 the CI run's own
  runner discovered there (Shell suites below), which
  lists the 18 suites this run reached. The runner starts the 12 serial suites first, then the rest
  longest first by `scripts/suite-seconds.txt`, so the 18 include the
  heaviest; the three slowest took 7 to 15 times their Linux CI time
  (`audit-engine.test.sh` 1660 s against 135). Nine of the 18 exited nonzero
  on this host; all passed on Linux CI at the same commit.
- **`scripts/affected-tests.sh --run` on a 50-file diff.** 130.8 s on a
  checkout of `62ee899e8f` (#12555, 47 files) with `--base 62ee899e8f~1`,
  over the 2-minute target. It selected 11 suites and ran the 5 shell
  suites, all passing, then exited 3 for the 6 Python and Node suites it
  selected but does not run.

## Gate scripts

With the default `--base origin/main` on an unchanged checkout, three gates see
an empty diff and time nothing, so the columns use a one-commit skill diff: a
checkout of `52a529d9cf` (#11995, a `skill-quality` skill change with its
changelog fragment) timed with `--base 52a529d9cf~1`. The Linux column is the
median of three runs on a WSL2 Linux host on 2026-11-02, not the CI runner;
every gate exited 0. The Windows column is the median of three runs of the
same commit and base on the Windows host above, on 2026-11-04; every gate
exited 0 and none took over 60 s. The first run's `check-purged-em-dashes.sh`
took 31.174 s against 17.069 and 17.376 s after it, a cold file cache.

| Gate | Invocation | Linux (s) | Windows Git Bash (s) |
| --- | --- | --- | --- |
| `scripts/check-purged-em-dashes.sh` | `--check` | 1.762 | 17.376 |
| `scripts/check-changed-skills.sh` | `<base>` | 1.178 | 17.414 |
| `scripts/check-changelog-parity.sh` | `--check-bump <base>` | 0.039 | 0.525 |
| `plugins/skill-quality/scripts/check-skill.sh` | `check`, skills root `plugins/skill-quality/skills`, base ref `<base>`, markdownlint skipped | 0.627 | 15.631 |
| `plugins/planning/scripts/check-open-questions.sh` | `--ledger <two answered rows>` | 0.012 | 0.214 |

## Shell suites

The Linux CI column is read from the `TIME:` lines of whole-tree run
[41211887017](https://github.com/melodic-software/claude-code-plugins/actions/runs/41211887017)
(`pr-require-checks`, `workflow_dispatch` on main at `fd862a49b848`,
2026-10-31, all seven `test-bash` legs green): 820 suites, 6254 suite-seconds in
total across the seven legs at `--jobs 3`. The per-suite seconds the runner
balances legs by are in `scripts/suite-seconds.txt`. The Windows column takes a
Git Bash run of the same tree's corpus on the Windows host above,
`origin/main`'s runner with `--root` at a checkout of `fd862a49b848`; a cell
with an exit code is a suite that failed there. The table holds only the 18
suites the 60-minute run reached.

Re-measured rows, from `run-plugin-tests.sh --timings` at `--jobs 1` on a native `C:` clone:
`audit-engine.test.sh` is 1336 s after #13229, against the 1660 s above (a 2714 s run just before
it overlapped other load on the host and is not a baseline). `audit-fleet.test.sh` is 269 s and
266 s after #13232, alternated with 544 s and 403 s before it, passing both times.
`cant-fail-scan.test.sh` is 993 s and 1069 s after #13231's process-start cut, alternated with
1294 s and 1421 s before it at `b70be89eb4`, on the same host on 2026-11-04, timed with Git Bash's
`time` on native `D:` worktrees rather than `run-plugin-tests.sh`; every run passed.

| Suite | Linux CI (s) | Windows Git Bash (s) |
| --- | --- | --- |
| `plugins/context-budget/skills/audit/scripts/measure.test.sh` | 8 | 17 (exit 1) |
| `plugins/desktop-notification/hooks/desktop-notification.test.sh` | 1 | 10 |
| `plugins/guardrails/hooks/block-dangerous-git.test.sh` | 22 | 126 (exit 1) |
| `plugins/guardrails/hooks/block-noncanonical-commit.test.sh` | 11 | 61 (exit 1) |
| `plugins/guardrails/hooks/skill-reference-verify.test.sh` | 5 | 81 |
| `plugins/harness-config/skills/audit/scripts/audit-engine.test.sh` | 135 | 1336 |
| `plugins/markdown-format/hooks/markdown-format.test.sh` | 7 | 51 (exit 1) |
| `plugins/performance/scripts/ab.test.sh` | 4 | 26 |
| `plugins/planning/shared/tests/ui-a.test.sh` | 195 | 7 (exit 1) |
| `plugins/planning/shared/tests/ui-b.test.sh` | 163 | 5 (exit 1) |
| `plugins/planning/shared/tests/ui-c.test.sh` | 171 | 9 (exit 1) |
| `plugins/planning/surface/surface-page.test.sh` | 93 | 93 (exit 1) |
| `plugins/playwright/skills/demo-video/scripts/demo-video.test.sh` | 266 | 0 |
| `plugins/repo-fleet-hygiene/skills/audit/scripts/audit-fleet.test.sh` | 34 | 268 |
| `plugins/skill-quality/scripts/check-listing-budget.test.sh` | 1 | 28 |
| `plugins/source-control/hooks/pr-body-linkage-gate.test.sh` | 13 | 60 |
| `plugins/testing/skills/audit/scripts/cant-fail-scan.test.sh` | 128 | 1069 |
| `plugins/spelling/hooks/spelling.test.sh` | 2 | 11 |
