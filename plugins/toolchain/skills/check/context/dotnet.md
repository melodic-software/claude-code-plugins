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

# Single test project (--project works under both VSTest and MTP; required under MTP)
dotnet test --project "$REPO_ROOT/path/to/Project.Tests.csproj"
```

## Lint / Format

Opt-in gated: only runs when a governing `.editorconfig` is present (see the
`opt-in` key and its header-comment rationale in
`reference/ecosystems/dotnet.yaml`). Otherwise it is skipped visibly rather
than imposing Roslyn's built-in formatting defaults on a repo that never
configured any.

```bash
# Check formatting (CI mode — fails on violations)
dotnet format "$REPO_ROOT/<solution>" --verify-no-changes

# Fix formatting
dotnet format "$REPO_ROOT/<solution>"
```

## Gotchas

- **`--project` is required** for test project paths **under the opt-in Microsoft.Testing.Platform (MTP) runner** (enabled via `global.json` / `dotnet.config`), where bare positional paths are rejected: `dotnet test path/to/Project.csproj` fails with "Specifying a project for 'dotnet test' should be via '--project'". Under VSTest, still the .NET 10 default, a bare positional project path is accepted. `--project` works in both, so prefer it either way (re-checked against Microsoft's dotnet-test-mtp/vstest docs, 2026-08-26)
- **`--nologo` breaks xUnit v3** MTP runner. The flag passes through to the xUnit executable which rejects it as "Unknown option". Result: zero tests ran, exit code 5. Same issue with `-v q`. Use plain `dotnet test` or `-v n`
- **`TreatWarningsAsErrors` repos**: when the repo turns warnings into errors globally, every warning is build-breaking; don't dismiss a warning as cosmetic
- **VS locks analyzer DLLs**: if `dotnet build` fails with MSB3021 while Visual Studio is open, close VS or skip analyzers for quick iteration
- **Binary log**: `dotnet build -bl` produces `msbuild.binlog` for diagnosing slow builds or property issues

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

Checks repos often gate in CI that plain build/test/format don't catch locally. Run them when the consuming project documents them:

- **Locked-mode NuGet restore** (`dotnet restore --locked-mode`): local `dotnet restore` is permissive; only locked-mode catches `packages.lock.json` drift. Remediation: `dotnet restore --force-evaluate`, commit the regenerated lockfiles. Cross-platform caveat: lockfiles generated on one OS can miss another OS's runtime transitives; regenerate on the CI OS (container/WSL) rather than forcing `-r <rid>`, which pollutes lockfiles with RID blocks
- **NU1507 on restore** (fails on a developer machine, passes in CI): with Central Package Management (`ManagePackageVersionsCentrally`) and `TreatWarningsAsErrors` both on, a user-level NuGet config that lists more than one package source raises NU1507 ("please map your package sources with package source mapping or specify a single package source"), and warnings-as-errors makes it fatal. A CI runner with one source never sees it. Remediation: a repo-level `nuget.config` that clears and pins `packageSources` (and `auditSources`), maps `<package pattern="*" />` to that source under `packageSourceMapping`, and clears `disabledPackageSources`, so every host restores from the same declared set. Do not pass `--source`, add NU1507 to `NoWarn`, or edit the user-level config: each clears one machine and leaves the repository's sources unpinned. Basis: [NU1507](https://learn.microsoft.com/en-us/nuget/reference/errors-and-warnings/nu1507) and [Package Source Mapping](https://learn.microsoft.com/en-us/nuget/consume-packages/package-source-mapping), fetched 2026-09-27. Recheck when either page changes NU1507's trigger or remedy, or when `melodic-software/standards` ships a `nuget.config` component, which this bullet then names instead of describing the file
- **Generated-artifact freshness** (e.g. a build-time OpenAPI spec): build the producing project, then `git diff --exit-code` on the generated file; stage the regenerated artifact alongside the source change
