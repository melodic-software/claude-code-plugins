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
  `gh run view --log --job <job-id>` and keep its `TIME:` lines; the seven legs
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

## Gate scripts

Each column is empty until `scripts/time-gates.sh` has run on that host.

| Gate | Invocation | Linux (s) | Windows Git Bash (s) |
| --- | --- | --- | --- |
| `scripts/check-purged-em-dashes.sh` | `--check` | | |
| `scripts/check-changed-skills.sh` | `<base>` | | |
| `scripts/check-changelog-parity.sh` | `--check-bump <base>` | | |
| `plugins/skill-quality/scripts/check-skill.sh` | `check`, skills root `plugins/skill-quality/skills`, base ref `<base>`, markdownlint skipped | | |
| `plugins/planning/scripts/check-open-questions.sh` | `--ledger <two answered rows>` | | |

## Shell suites

The Linux CI column is read from the `TIME:` lines of whole-tree run
[41211887017](https://github.com/melodic-software/claude-code-plugins/actions/runs/41211887017)
(`pr-require-checks`, `workflow_dispatch` on main at `fd862a49b848`,
2026-10-31, all seven `test-bash` legs green). Its job logs need an
authenticated read, so the rows below are empty until someone with `gh` access
fills them. The Windows column takes a Git Bash run of the same tree's
corpus, and is empty until one is made.

| Suite | Linux CI (s) | Windows Git Bash (s) |
| --- | --- | --- |
