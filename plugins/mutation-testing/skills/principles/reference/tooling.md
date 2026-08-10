# Tools by ecosystem, and what to do without one

Which mutation tool exists for which stack, what each one calls things, and the honest answer for
languages nobody has built a tool for.

Sources: [Stryker](https://stryker-mutator.io/), [PIT](https://pitest.org/),
[Infection](https://infection.github.io/), [mutmut](https://mutmut.readthedocs.io/). Fetched
2026-08-10.

## Established tools

| Ecosystem | Tool | Diff-scoping flag | Covered-code metric name |
|---|---|---|---|
| JavaScript / TypeScript | StrykerJS | `--incremental` | Mutation score based on covered code |
| C# / .NET | Stryker.NET | `--since[:<target>]` | Mutation score based on covered code |
| Scala | Stryker4s | `--since` | Mutation score based on covered code |
| Java / JVM | PIT (pitest) | incremental analysis | **Test strength** |
| PHP | Infection | `--git-diff-lines` | **Covered Code MSI** |
| Python | mutmut | changed-file selection | mutation score |

Names differ; the metric is the same one. See [metrics.md](metrics.md).

## Selecting a tool

Read the consuming project before choosing:

1. **Detect the ecosystem** from what exists — `package.json`, `*.csproj` / `*.sln`,
   `pom.xml` / `build.gradle`, `composer.json`, `pyproject.toml` / `setup.cfg`.
2. **Confirm the test runner is one the tool supports.** This is the usual blocker: a mutation tool
   drives the test runner, so an unsupported or heavily customized runner setup fails before any
   mutant runs.
3. **Confirm the suite is green and non-flaky first.** A red suite kills every mutant and reports a
   perfect score. A flaky suite kills mutants at random. Neither result means anything.
4. **Confirm the suite is fast enough per covered file.** Mutation cost is dominated by repeated
   suite execution. If the tool cannot select a subset of tests per mutant, the run scales with the
   whole suite and diff-scoping is the only thing keeping it affordable.

## Configuration that matters more than the rest

Whatever the tool, three settings carry most of the value:

- **Diff target** — the ref to compare against. Get this wrong and the run either covers nothing or
  covers everything.
- **Operator set** — start with defaults. Optional and experimental operators raise both mutant
  count and unproductive rate.
- **Timeout** — too tight and slow-but-correct code reports false timeouts; too loose and an
  infinite-loop mutant burns the run. Tools derive a default from baseline suite time; override only
  with a measurement.

Deliberately not recommended: a break-on-threshold setting. See
[scaling-and-suppression.md](scaling-and-suppression.md) for why gating on the score inverts the
incentive.

## When no tool exists for the language

Shell, Terraform, SQL, and plenty of others have no mutation tooling. The technique still applies by
hand or by agent, but the honesty bar rises because nothing is checking the harness.

A defensible manual pass needs all five:

1. **A single operator, applied once.** Prefer statement/block removal (SBR) — the highest-yield
   operator, and the one needing no parser. Inverting a comparison is the second.
2. **A recorded baseline.** Run the covering tests *before* mutating and record the result. Without
   it, a "killed" verdict cannot be distinguished from a suite that was already red.
3. **A bounded test selection.** Know which suites cover the mutated file, and run those. Mutating a
   widely-depended-on file and running everything makes each mutant cost a full suite run.
4. **Guaranteed revert.** The mutation must be undone whether the run passes, fails, or errors. Prefer
   applying it as a patch that is reverted in a trap/finally, never an edit that depends on a later
   step to clean up.
5. **A cited verdict for anything called unkillable.** An equivalence claim asserted from inspection
   is where this technique manufactures false confidence. Cite the measurement — the two runs and
   what was identical about them.

That last point is not theoretical. This repository's own `lib/hook-utils.test.sh` carries a worked
example: a block deleted from `hook-utils.sh`, a baseline and mutant run measured and reported
(`rc=0 len=65536` in both, 2948 ms against 5823 ms), the survivor diagnosed, the test redesigned
around a non-temporal observable so it would go red, and the one delivery shape under which the
mutant is genuinely undetectable documented with the measurement that established it. That is the
bar.
