# Tool test restriction

Whether each probed mutation tool can run its mutants against a named test set, and whether it
keeps its no-coverage state (a mutant no restricted test reaches reports NoCoverage) under that
restriction. The audit's exercised scope uses a tool's restriction only when this column reads
`yes`; a tool with `no` or `unknown` runs under the manual protocol with `test-command`. stryker4s,
pitest and infection are not probed and use the manual protocol.

| Tool | Option | Granularity | Coverage/dry-run interaction | Keeps no-coverage | Source | Fetched |
|---|---|---|---|---|---|---|
| stryker-js | `testFiles` (CLI `--testFiles "a.spec.js","b.spec.js"`) | file | Docs: "only tests from these files will be run". `coverageAnalysis` computes coverage in the initial test run and reports mutants without coverage as NoCoverage, but no page states that the initial run is restricted by `testFiles`, so the combination is inferred, not documented. | unknown | https://stryker-mutator.io/docs/stryker-js/configuration/#testfiles-string, https://stryker-mutator.io/docs/stryker-js/configuration/#coverageanalysis-string | 2026-10-01 |
| stryker-net | `test-case-filter` (a `dotnet test --filter` expression; `test-projects` selects whole projects) | case | Docs: the filter runs Stryker "only on a selective subset of tests", and `coverage-analysis` `perTest` reports mutants without tests as NoCoverage, but the page does not state whether the filter applies to the initial coverage run. | unknown | https://stryker-mutator.io/docs/stryker-net/configuration/#test-case-filter-string, https://stryker-mutator.io/docs/stryker-net/configuration/#coverage-analysis-string | 2026-11-21 |
| mutmut | `pytest_add_cli_args_test_selection` (e.g. `["tests/test_a.py", "-k", "name"]`; mutmut 3.8.0) | file or case (any pytest selection argument) | Docs: mutmut runs the test suite once in the main process to collect stats, then forks one child per mutant; the selection arguments are the ones that choose and deselect tests. The README does not describe a NoCoverage state or how a restricted selection changes the stats run. | unknown | https://github.com/boxed/mutmut | 2026-10-01 |

## `test-command` filter forms

A runner's kind decides whether `test-command` can carry `{tests}`:

- **Path list**: the runner's command line takes test files as arguments. `test-command` is that
  command with `{tests}` as a standalone word where the paths go.
- **Name filter only**: the runner selects tests only by class, method or pattern name. It has no
  `{tests}` form.

Read the kind from the repository's own test configuration and the runner's own help output or
documentation for the version the repository uses. When neither settles it, the kind is unknown and
counts as name filter only. A runner a bundled script drives has its own form and kind, listed
below, in place of these two.

| Ecosystem | Runner | Form | Kind | Source |
|---|---|---|---|---|
| .NET | dotnet test (VSTest runner) | `dotnet test {tests}`, run once per line `scripts/dotnet-test-selection.sh <test file>...` prints: the owning project, then `--filter 'FullyQualifiedName~<Namespace>.<Class>.\|...'` for each top-level class in that project's files, plus `<Class>+` for a class holding nested classes and no trailing dot for a generic one (`~` is contains, `\|` is or; there is no file path form). Keep `--filter` out of `test-command`. A baseline whose filter matches no test refuses: [Running a .NET test set](#running-a-net-test-set) | project and name filter | https://learn.microsoft.com/en-us/dotnet/core/testing/selective-unit-tests, https://learn.microsoft.com/en-us/dotnet/core/tools/dotnet-test-vstest |

Recheck trigger: a new major release of StrykerJS, Stryker.NET or mutmut, or a change to the named option on its configuration docs page. For the .NET row and [Running a .NET test set](#running-a-net-test-set): a change to the filter syntax on the selective-tests page, or to the project argument or the no-matching-tests exit code on the VSTest `dotnet test` page (both read 2026-10-26).

## Running a .NET test set

When `test-command` starts with `dotnet test`, the exercised scope runs the bundled
`scripts/dotnet-test-selection.sh` (SKILL.md names its path) over the test set, from the directory
`test-command` runs in. It prints one already-quoted line per owning project. Every run of the
test set runs `test-command` once per line, with `{tests}` replaced by that line, and any red run
makes the set red. A non-zero exit from the script refuses. A baseline run that reports no test
matching the filter refuses: a filter that matches no test still exits 0, so that baseline can
pass with nothing run. Never run `dotnet test` without a project argument, a baseline included.
