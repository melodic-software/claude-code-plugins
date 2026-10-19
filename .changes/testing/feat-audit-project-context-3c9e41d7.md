---
bump: minor
---

### Added

- `/testing:audit` findings carry `[project: ...; ci: yes|no|unknown; kind: ...]`: the owning C# project (nearest `.csproj`), whether a `.github/workflows` `dotnet test` or `dotnet build` targets it, and its kind (`unit`, `integration`, `functional`, `architecture`, `live`, `operational`) from name tokens and package references, or `unknown`. A finding in a `live` or `operational` project (`*.Provisioning.*`, `*.Smoke.*`) warns not to run its tests, and findings in CI-run unit projects rank first. A new `project_kinds` config key (`<glob>=<kind>`) overrides the kind. Nothing is built or run, and a workflow that does not parse gives `ci: unknown`.
