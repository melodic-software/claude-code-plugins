# Run estimate

How Phase 1 step 5 takes the two numbers the bundled `scripts/estimate-run.sh` (SKILL.md names its
path) turns into the estimated wall-clock line. `--full` prints the same line before it confirms.

**The seconds.** A mutant can cost a rebuild as well as a test run, so time one build plus test run
of the selection Phase 1 step 4 cached (for a .NET test set, `dotnet test` over each line
`dotnet-test-selection.sh` prints for it, summed, since each mutant runs every line). Time it as a
mutant pays it: a build that reuses cached output recompiles nothing a mutant would, so where the
build cannot be made to recompile without editing tracked source, say the estimate is a floor. Pass
that timing as `--seconds`, in seconds to at most three decimal places.

**The mutant count.** Take it from the configured tool's dry run or mutant listing; under
`tool: manual`, it is the mutants Phase 2 will apply. Pass it as `--mutants`.

Never do the arithmetic yourself: the line reported is the line the script prints.
