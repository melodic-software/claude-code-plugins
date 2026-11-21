---
bump: patch
---

### Changed

- **`/testing:diagnose` and `/testing:plan` no longer ship ecosystem-specific examples.** Diagnose drops its .NET test-runner gotcha, the WebApplicationFactory, `--nologo` and `.Result`/`.Wait()` wording from its failure table, the xUnit, pytest and vitest filter flags, the pytest-randomly and `go test -shuffle` seed flags, and the illustrative `dotnet test` block in the regression step. Plan drops WebApplicationFactory, Testcontainers, Docker Compose, EF and Blazor from its file-type table and the .NET/xUnit name pattern from its plan template. The filter and seed flags now come from the test runner's own docs, and the regression command from `/toolchain:check` ([#17741](https://github.com/melodic-software/claude-code-plugins/issues/17741)).
