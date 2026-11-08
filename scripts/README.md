# Repository scripts

`scripts/` holds this repository's CI checks, sync scripts, and catalog generators, with their tests
beside them. This page covers running them before you push.

- [Validate a change](#validate-a-change)
- [Per-suite time budget in CI](#per-suite-time-budget-in-ci)
- [Local pre-flight for hygiene gates](#local-pre-flight-for-hygiene-gates)
- [The check-script contract](#the-check-script-contract)

## Validate a change

Run the suites that cover your change, not every `**/*.test.sh`. The shell suites are spawn-bound:
Git Bash on Windows pays roughly 140 ms per process spawn against roughly 3 ms on Linux, so a full
local run takes hours on a Windows host.

```shell
scripts/affected-tests.sh                 # list the suites covering your diff vs origin/main
scripts/affected-tests.sh --run           # ... and run them, sequentially
scripts/affected-tests.sh --explain       # ... and say why each one was selected
scripts/affected-tests.sh path/to/file.sh # explicit paths instead of a diff
scripts/check-affected.sh [--tests]       # CI's diff-scoped lint checks (+ the suites); runs before every agent git push
```

`--run` is a Linux gate. On a Windows Git Bash host a standing set of suites
fails for reasons that belong to the host rather than to the tree: text-mode
CRLF translation (a native jq and Git Bash line-ending handling), no
unprivileged symlink right, MSYS drive-letter paths against the POSIX form in
fixture assertions, and a missing `scc`. Its exit code there reports host
capability, not whether your change is good, so Windows is not a supported host
for the full `--run` gate ([#3966](https://github.com/melodic-software/claude-code-plugins/issues/3966)).
Selection itself is host-neutral: on Windows, use the listing forms above to see
what your change affects and run individual suites by hand. CI's Linux lanes are
the gate that decides.

It maps a changed file to its co-located suite, to any suite that names it, and
to its dependents transitively, and it fans a shared-lib change out to every
carrying plugin by reading the `--print-manifest` output of each
`scripts/sync-*.sh` script, the same manifests CI's sync steps enforce. The
fan-out is derived on every run, never transcribed, so a new carrying plugin is
covered the moment it exists.

All four ecosystems that carry suites here are selected, each by its own naming
convention: shell `*.test.sh`, Node `*.test.js` and `*.test.mjs`, Python
`test_*.py`, and Pester `*.Tests.ps1`. Only the shell suites are executed by
`--run`, because the others are driven by lane-specific invocations that cannot
be derived from a suite path; those are named as `NOT RUN` and `--run` exits 3
rather than reporting success over suites that never executed.

A changed file that maps to nothing is an **error**, not an empty selection:
"zero suites" must never be read as "nothing to run". Path classes that
genuinely carry no suite are recorded, with the CI lane that does cover them, in
[`affected-tests-no-suite.txt`](affected-tests-no-suite.txt);
`--allow-unmapped` is the escape hatch for everything else. That list is for
prose and manifests, never for code: a source file with no coverage is supposed
to fail here. A **deletion** is the one exception: a changed path that no longer
exists and that nothing claims is reported as a visible `deleted:` note instead
of the error, because there is no content left to cover. A deletion that a
surviving suite still names (a co-located test left behind, a suite that
references the dead path) keeps selecting those suites, which are exactly what
fails loudly if the deletion broke something.

The runner is sequential: parallelising it measured sublinear (the suites are
spawn-bound), and several guardrails suites assert wall-clock ceilings that fail
spuriously under concurrency. Selection is what shortens a run. CI still runs
everything.

## Per-suite time budget in CI

On GitHub Actions, `scripts/run-plugin-tests.sh` times each shell suite a
`test-bash` leg runs:

| Suite wall time | Result |
|---|---|
| over 120 s | `SLOW:` line and a warning annotation naming the suite; the leg still passes |
| over 300 s | `FAIL:` line and an error annotation; the leg fails |

Basis, from the shell medians in [`suite-seconds.txt`](suite-seconds.txt) (measured on
`ubuntu-24.04` CI runners through 2026-10-28):

- 120 s is the work the planner packs into one `test-bash` leg, so a suite
  over it fills a leg on its own. Twelve shell suites are over it.
- 300 s is more than half of a leg's 9-minute limit. No shell suite outside
  the exception list has a median over 150 s, half the ceiling.

A suite that needs more gets a row with its own ceiling in
[`suite-budget-exceptions.txt`](suite-budget-exceptions.txt),
so the exception shows in review. The ten suites with a median over 150 s
start there at 480 s. Outside CI the check is off, since the numbers are CI
runner times; `PLUGIN_TEST_SUITE_BUDGET=1` turns it on. Python suites in the
`test-python` lane are not budgeted. Every run, in CI or not, prints a
`TIME: <suite> <seconds>s` line after each suite's result, so a leg's log shows
the time each suite took.

## Local pre-flight for hygiene gates

A CI gate's name is not its local command, so several hygiene findings only show up after a push.
Every gate below has a local form.

| CI gate / step id | Local command | Notes |
|---|---|---|
| `plugin-options-docs` | `python3 scripts/sync-plugin-options-docs.py --check` | Regenerates from `plugin.json` `userConfig`. Do not hand-edit the README block. |
| `config-cascade-semantics` | `python3 scripts/sync-config-cascade-semantics.py --check` | Regenerates the glance table from the Implementers rows; run it without `--check` after editing a row. Do not hand-edit the generated block. |
| `typos` | `typos --config _typos.toml` | Same config CI passes to the composite. |
| `markdown` | `markdownlint-cli2` | Config: `.markdownlint-cli2.jsonc`. |
| `purged-em-dashes` | `scripts/check-purged-em-dashes.sh` | In-repo. |
| `changelog-parity` | `scripts/check-changelog-parity.sh --check` | In-repo; add `--check-bump origin/main` for the version-bump check. A bare run exits 2 with a usage message. |
| `shell-portability` | `scripts/check-shell-portability.sh origin/main` | In-repo; `--all` scans the whole tree. A bare run exits 2 with a usage message. |
| `comment-hygiene` | `bash scripts/check-comment-hygiene.sh origin/main <files>` | In-repo wrapper; fetches the pinned `check-comment-markers` action's own patterns library at the SHA `origin/main`'s workflow pins, so it needs network. File paths are relative to the repository root. |
| `machine-specific-paths` | `EXTENSIONS='<extensions>' EXCLUDE='<excludes>' bash <ci-workflows-checkout>/.github/actions/check-machine-paths/check-machine-specific-paths.sh` | Run from the repository root. See [Running `machine-specific-paths` locally](#running-machine-specific-paths-locally). `scripts/check-affected.sh` runs the same scan on the changed files without a `ci-workflows` checkout. |

`scripts/check-affected.sh` runs the rows that apply to a diff, `typos`, `machine-specific-paths`, `plugin-options-docs`, `changelog-parity`, `comment-hygiene` and `markdown` among them, and prints `CI only: <gate>` for every hygiene gate it leaves to CI, the whole-repo scanners included. Its `machine-specific-paths` check repeats the composite's scan and exemptions over `plugins/guardrails/lib/path-detection/machine-path-patterns.sh`, the copy of the patterns file the composite sources, with the `exclude:` pathspecs and any `extensions:` of the workflow step, read from the workflow on each run. `scripts/check-affected-gates.txt` lists each gate and how it is covered.
`scripts/aggregate-hygiene-results.sh` consumes CI step outcomes; it does not run the gates.

- **Claim:** every row of the mapping table is a local command; `machine-specific-paths` runs the
  pinned composite's own entry script.
- **Basis:** the #3522 owner decision (document running the composite's script from a
  `ci-workflows` checkout). Verified: the script runs standalone and needs only `EXTENSIONS` and
  `EXCLUDE`.
- **As of:** `ci-workflows` `2476d5dde8979eab34374150b7e4b0a2b99f4e88`, the pin in
  `.github/workflows/pr-require-checks.yml`, re-verified on 2026-11-06: no file under
  `.github/actions/check-machine-paths/` changed since the 2026-10-21 check at `5e18f3d6`.
- **Recheck:** the `pr-require-checks.yml` pin moves, or the composite's entry script changes its environment
  contract, its scan or its exemptions, which `scripts/check-affected.sh` repeats.

### Running `machine-specific-paths` locally

The gate is a composite in `melodic-software/ci-workflows`. Its entry script runs standalone, but it
sources `machine-path-patterns.sh` from its own directory, so run it in place from a `ci-workflows`
checkout.

1. In the `Check for machine-specific paths` step of `.github/workflows/pr-require-checks.yml`, read the pinned SHA
   from the `uses:` line and the `:(exclude)...` pathspecs from the `exclude:` input.
2. Check out `ci-workflows` at that SHA:
   `git -C <ci-workflows-checkout> switch --detach <sha>` (or add a worktree at the SHA).
3. From the repository root, run the row's command with `EXTENSIONS` set to the action's default,
   `*.cs *.csproj *.json *.jsonc *.js *.jsx *.md *.props *.ps1 *.psm1 *.py *.sh *.slnx *.targets *.toml *.ts *.tsx *.yaml *.yml`,
   and `EXCLUDE` set to the `exclude:` pathspecs joined by spaces.

The script uses `git grep` in the current directory: it scans tracked files only, so `git add -N`
or commit a new file before running. Exit 0 is clean, exit 1 means findings.

## The check-script contract

`scripts/check-*.sh` is one family with one caller-visible interface, so a CI
lane, a wrapper, or an agent reads a run's outcome without knowing which member
produced it.

| Exit | Meaning |
|---|---|
| `0` | Clean. The check ran over its whole corpus and found nothing. |
| `1` | Findings. The check ran and something in the tree is wrong. |
| `2` | Environment or usage. The check could not run: a missing tool, a bad argument, a repo root or shared library that did not resolve, a git query that failed. Nothing was inspected, so this is never a pass. |

Findings and diagnostics go to **stderr**; **stdout** carries the clean-run
statement and, for the discovery or list modes some members offer, the report
that mode exists to print.

Exits `1` and `2` stay apart because "your tree is wrong" and "I could not
look" are different answers, and a lane that reads only success or failure
collapses them into one. This is the mechanical form, for this family, of the
fail-loud rule in
[`docs/contracts/liveness-assertion/`](../docs/contracts/liveness-assertion/README.md).
An environment failure is spelled out rather than left to `set -e`: resolving the
repo root and sourcing a shared library each end in `|| exit 2`, because `set -e`
would exit with the failing command's own status and hand the caller a `1` that
reads as findings.

[`check-script-contract.test.sh`](check-script-contract.test.sh)
holds the contract. Every member is registered there and a new one fails as
unregistered. Each member that declares a prerequisite is run with that
prerequisite taken away and must exit `2` on stderr; each member with a fixture
recipe is also run clean (exit `0`, statement on stdout) and against a seeded
violation (exit `1`, finding on stderr and not on stdout). A member with no
recipe yet is held to those last two halves by its own co-located suite.

Three members diverge on purpose:

- `scripts/check-hook-exec-form.sh` treats a hook declaration it cannot parse as
  a finding (`1`), not an environment problem. The input is what is wrong, and
  clearing a file the gate never read is the silent no-op it exists to catch.
- `scripts/check-killswitch-hoist.sh` stops at `1`, not `2`, when the hook corpus
  scans to empty or the inlined kill-switch predicate no longer agrees with the
  `hook::is_enabled` it duplicates. Both are statements about the tree, not about
  the host.
- `scripts/check-changelog-parity.sh` discusses exit `128` and `141` at length
  and emits neither. Those are git's "no merge base" and a reader killed by
  SIGPIPE, each converted to an `exit 2` or read correctly. Grepping the file for
  those numbers finds the guards, not divergence.

The contract governs the observable interface, not the option set: `set -euo`
and `set -uo` both appear in the family and neither is required, which is why
the prologue states its own `|| exit 2` instead of depending on which one is in
force. Members still resolving the repo root under `set -e` alone are aligned on
touch.
