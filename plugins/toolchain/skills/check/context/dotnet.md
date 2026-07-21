# .NET Build Commands

`<solution>` below is the repo's solution file (`*.slnx` or `*.sln`, usually at repo root). When the repo has no solution, target the relevant `.csproj` directly.

## Build

```bash
# Full solution (from repo root)
dotnet build "$REPO_ROOT/<solution>"

# Single project
dotnet build "$REPO_ROOT/path/to/Project.csproj"

# Fast inner-loop (skip analyzers, when the repo wires a SkipAnalyzers property)
dotnet build -p:SkipAnalyzers=true "$REPO_ROOT/path/to/Project.csproj"

# Build with SARIF v2.1.0 diagnostics (per-project, absolute path)
dotnet build "$REPO_ROOT/path/to/Project.csproj" \
  "-p:ErrorLog=$REPO_ROOT/artifacts/Project.sarif%3bversion=2.1" \
  --nologo -v q
# See [context/sarif.md](sarif.md) for parser patterns and the SARIF gap.
```

## Test

```bash
# All tests via solution
dotnet test "$REPO_ROOT/<solution>" --no-build

# Single test project (.NET 10 requires --project flag)
dotnet test --project "$REPO_ROOT/path/to/Project.Tests.csproj"
```

## Lint / Format

Opt-in gated: only runs when a governing `.editorconfig` is present (see the
`opt-in` key and its header-comment rationale in
`reference/ecosystems/dotnet.yaml`) — otherwise skipped visibly rather than
imposing Roslyn's built-in formatting defaults on a repo that never
configured any.

```bash
# Check formatting (CI mode — fails on violations)
dotnet format "$REPO_ROOT/<solution>" --verify-no-changes

# Fix formatting
dotnet format "$REPO_ROOT/<solution>"
```

## Gotchas

- **`--project` is required** for test project paths in .NET 10 SDK (10.0.1xx+). Bare positional paths are rejected: `dotnet test path/to/Project.csproj` fails with "Specifying a project for 'dotnet test' should be via '--project'"
- **`--nologo` breaks xUnit v3** MTP runner. The flag passes through to the xUnit executable which rejects it as "Unknown option". Result: zero tests ran, exit code 5. Same issue with `-v q`. Use plain `dotnet test` or `-v n`
- **`TreatWarningsAsErrors` repos** — when the repo turns warnings into errors globally, every warning is build-breaking; don't dismiss a warning as cosmetic
- **VS locks analyzer DLLs** — if `dotnet build` fails with MSB3021 while Visual Studio is open, close VS or skip analyzers for quick iteration
- **Binary log** — `dotnet build -bl` produces `msbuild.binlog` for diagnosing slow builds or property issues

## Project discovery and targeting

Choose the scope based on what changed:

| What changed | Build scope | Command |
|-------------|------------|---------|
| Files in a single project | That project's `.csproj` | `dotnet build path/to/Project.csproj` |
| Files spanning multiple projects | Full solution | `dotnet build <solution>` |
| Shared build config (`.props`, `.targets`, `.editorconfig`) | Full solution | `dotnet build <solution>` |
| Nothing (clean tree, `/toolchain:check all`) | Full solution | `dotnet build <solution>` |

To find the `.csproj` for a changed file, walk up from the file's directory until you find a `.csproj`.

## Common project-declared CI-parity gates

Checks repos often gate in CI that plain build/test/format don't catch locally — run them when the consuming project documents them:

- **Locked-mode NuGet restore** (`dotnet restore --locked-mode`) — local `dotnet restore` is permissive; only locked-mode catches `packages.lock.json` drift. Remediation: `dotnet restore --force-evaluate`, commit the regenerated lockfiles. Cross-platform caveat: lockfiles generated on one OS can miss another OS's runtime transitives; regenerate on the CI OS (container/WSL) rather than forcing `-r <rid>`, which pollutes lockfiles with RID blocks
- **Generated-artifact freshness** (e.g. a build-time OpenAPI spec) — build the producing project, then `git diff --exit-code` on the generated file; stage the regenerated artifact alongside the source change

## Marketplace plugin skills for build diagnostics (invoke only when installed)

These are .NET-ecosystem plugin skills — applicable when your stack is .NET — and forward references to the planned `dotnet-*` plugin family: invoke each only when its plugin is installed, otherwise fall back to the prose remediation and the binlog gotcha above.

- **Slow builds** — `dotnet-msbuild:build-perf-diagnostics` for bottleneck analysis via binary logs, `dotnet-msbuild:build-perf-baseline` for before/after measurement
- **Build failures** — `dotnet-msbuild:binlog-failure-analysis` to diagnose opaque MSBuild errors, `dotnet-msbuild:binlog-generation` for binary log capture (`dotnet build /bl:{}`)
- **Build config issues** — `dotnet-msbuild:msbuild-antipatterns` for AP-01 through AP-21, `dotnet-msbuild:check-bin-obj-clash` for OutputPath conflicts
