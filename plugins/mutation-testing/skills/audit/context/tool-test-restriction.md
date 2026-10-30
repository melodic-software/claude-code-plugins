# Tool test restriction

Whether each probed mutation tool can run its mutants against a named test set, and whether it
keeps its no-coverage state (a mutant no restricted test reaches reports NoCoverage) under that
restriction. The audit's exercised scope uses a tool's restriction only when this column reads
`yes`; a tool with `no` or `unknown` runs under the manual protocol with `test-command`. stryker4s,
pitest and infection are not probed and use the manual protocol.

| Tool | Option | Granularity | Coverage/dry-run interaction | Keeps no-coverage | Source | Fetched |
|---|---|---|---|---|---|---|
| stryker-js | `testFiles` (CLI `--testFiles "a.spec.js","b.spec.js"`, default `[]`) | file | Docs: "only tests from these files will be run". `coverageAnalysis` (default `perTest` since Stryker v5) computes coverage in the initial test run and reports mutants without coverage as NoCoverage, but no page states that the initial run is restricted by `testFiles`, so the combination is inferred, not documented. | unknown | https://stryker-mutator.io/docs/stryker-js/configuration/ | 2026-10-01 |
| stryker-net | `test-case-filter` (a `dotnet test --filter` expression, set in the config file: 5.0.0 has no CLI flag for it, though the page lists `--test-case-filter`; `test-projects` selects whole projects). Built and passed as [Running Stryker.NET on a test set](#running-strykernet-on-a-test-set) says | case | Probe #9687 (Stryker.NET 5.0.0, probed 2026-10-29 on Linux with .NET SDK 10.0.403, `coverage-analysis` `perTest`, the `dotnet-test-selection` fixture retargeted to net10.0): the filter applies in the initial coverage run (tests found fell from 5 to 2 with one test project and from 9 to 2 with both), and a mutant reached only by excluded tests reported NoCoverage, not Survived or Killed. With `test-projects` naming one of the two projects that reference the shared library, only that project's tests count for coverage and kills. The docs page does not state this; recheck on a new Stryker.NET release or a change to `test-case-filter` or `coverage-analysis` on that page. | yes | https://stryker-mutator.io/docs/stryker-net/configuration/#test-case-filter-string | 2026-10-29 |
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

## Running Stryker.NET on a test set

When the configured tool is Stryker.NET, the exercised scope runs `scripts/dotnet-test-selection.sh`
over the test set from the directory Stryker runs in. A non-zero exit refuses. From its lines it
builds two values: `test-projects`, each line's project; and `test-case-filter`, the lines'
`--filter` expressions joined with `|`, wrapped as `(<existing>)&(<built>)` when the project's
config already sets one. It writes them into a copy of the project's Stryker config file (default
`stryker-config.json`; with none, a file holding only a `stryker-config` section), under the
caller's gitignored `.work/`, and runs Stryker with `-f|--config-file` naming that copy relative to
the directory Stryker runs in (5.0.0 `--help`: "relative to current working directory"). Both values
go in the copy because the page does not say whether a CLI option overrides the config file. The
user's config file is never edited; delete the copy however the run ends. Sources:
https://stryker-mutator.io/docs/stryker-net/configuration/#test-case-filter-string,
https://stryker-mutator.io/docs/stryker-net/configuration/#test-projects-string,
https://stryker-mutator.io/docs/stryker-net/configuration/#config-file-path (read 2026-10-29).
