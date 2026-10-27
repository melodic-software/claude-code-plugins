---
bump: minor
---

### Added

- **`scripts/estimate-run.sh --mutants <n> --seconds <s>`** prints `Estimated wall-clock: <h>h <m>m (<n> mutants x <s>s per build-and-test)`, rounded up to the minute in exact integer arithmetic, with its test.

### Changed

- **`audit` estimates a run from a timed build and test run, not `baseline-suite-ms`.** Before any mutation run it times one build plus test run of the selected tests (every `dotnet-test-selection.sh` line, summed, for a .NET test set), takes the mutant count from the tool's dry run or listing, and prints the line `estimate-run.sh` computes; where the build cannot be made to recompile without editing tracked source, it says the estimate is a floor. `--full` confirms against the same line.
