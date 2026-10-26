# Tool test restriction

Whether each probed mutation tool can run its mutants against a named test set, and whether it
keeps its no-coverage state (a mutant no restricted test reaches reports NoCoverage) under that
restriction. The audit's exercised scope uses a tool's restriction only when this column reads
`yes`; a tool with `no` or `unknown` runs under the manual protocol with `test-command`. stryker4s,
pitest and infection are not probed and use the manual protocol.

| Tool | Option | Granularity | Coverage/dry-run interaction | Keeps no-coverage | Source | Fetched |
|---|---|---|---|---|---|---|
| stryker-js | `testFiles` (CLI `--testFiles "a.spec.js","b.spec.js"`, default `[]`) | file | Docs: "only tests from these files will be run". `coverageAnalysis` (default `perTest` since Stryker v5) computes coverage in the initial test run and reports mutants without coverage as NoCoverage, but no page states that the initial run is restricted by `testFiles`, so the combination is inferred, not documented. | unknown | https://stryker-mutator.io/docs/stryker-js/configuration/ | 2026-10-01 |
| stryker-net | `test-case-filter` (a `dotnet test --filter` expression; `test-projects` selects whole projects) | case | Docs: "Filter expression to run selective tests". With `coverage-analysis` `perTest`, mutants without tests are reported as NoCoverage. The page does not say how the filter interacts with the coverage phase. | unknown | https://stryker-mutator.io/docs/stryker-net/configuration/ | 2026-10-01 |
| mutmut | `pytest_add_cli_args_test_selection` (e.g. `["tests/test_a.py", "-k", "name"]`; mutmut 3.8.0) | file or case (any pytest selection argument) | Docs: mutmut runs the test suite once in the main process to collect stats, then forks one child per mutant; the selection arguments are the ones that choose and deselect tests. The README does not describe a NoCoverage state or how a restricted selection changes the stats run. | unknown | https://github.com/boxed/mutmut | 2026-10-01 |

## `test-command` filter forms

| Ecosystem | Runner | Form | Kind | Source |
|---|---|---|---|---|
| JavaScript/TypeScript | vitest | `npx vitest run {tests}` (positional filters match by path substring, not glob or regexp) | path list | https://vitest.dev/guide/cli.html |
| JavaScript/TypeScript | jest | `npx jest --runTestsByPath {tests}` | path list | https://jestjs.io/docs/cli |
| JavaScript/TypeScript | mocha | `npx mocha {tests}` | path list | https://mochajs.org/ |
| .NET | dotnet test (VSTest runner) | `dotnet test {tests}`, run once per line `scripts/dotnet-test-selection.sh <test file>...` prints: the owning project, then `--filter 'FullyQualifiedName~<Namespace>.<Class>.\|...'` for each top-level class in that project's files, plus `<Class>+` for a class holding nested classes and no trailing dot for a generic one (`~` is contains, `\|` is or; there is no file path form). Keep `--filter` out of `test-command`. A filter that matches no test still exits 0, with a warning | project and name filter | https://learn.microsoft.com/en-us/dotnet/core/testing/selective-unit-tests, https://learn.microsoft.com/en-us/dotnet/core/tools/dotnet-test-vstest |
| JVM | maven surefire | `mvn test -Dtest=<class or pattern>` | name filter only | https://maven.apache.org/surefire/maven-surefire-plugin/examples/single-test.html |
| JVM | gradle | `gradle test --tests "<class or pattern>"` | name filter only | https://docs.gradle.org/current/userguide/java_testing.html |
| PHP | phpunit | `vendor/bin/phpunit {tests}` | path list | https://docs.phpunit.de/en/12.0/textui.html |
| Python | pytest | `python -m pytest {tests}` | path list | https://docs.pytest.org/en/stable/how-to/usage.html |
| Python | unittest | `python -m unittest {tests}` (test modules may be given as file paths) | path list | https://docs.python.org/3/library/unittest.html |

Recheck trigger: a new major release of StrykerJS, Stryker.NET or mutmut, or a change to the named option on its configuration docs page. For the .NET row: a change to the filter syntax on the selective-tests page, or to the project argument or the no-matching-tests exit code on the VSTest `dotnet test` page (both read 2026-10-26).

## Running a .NET test set

When `test-command` starts with `dotnet test`, the exercised scope runs the bundled
`scripts/dotnet-test-selection.sh` (SKILL.md names its path) over the test set, from the directory
`test-command` runs in. It prints one already-quoted line per owning project. Every run of the
test set runs `test-command` once per line, with `{tests}` replaced by that line, and any red run
makes the set red. A non-zero exit from the script refuses. A baseline run that reports no test
matching the filter refuses: a filter that matches no test still exits 0, so that baseline can
pass with nothing run. Never run `dotnet test` without a project argument, a baseline included.
