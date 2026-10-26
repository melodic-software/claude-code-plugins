---
bump: minor
---

### Added

- **`audit --exercised` runs on .NET.** A new `scripts/dotnet-test-selection.sh` groups test files by their nearest `.csproj` and prints one quoted line per project: the project path, then a `--filter` of `FullyQualifiedName~<Namespace>.<Class>.` terms for every top-level class in those files (plus `<Class>+` for a class holding nested classes, and no trailing dot for a generic class). When `test-command` starts with `dotnet test`, the audit runs it once per printed line in place of `{tests}`, refuses a baseline in which no test matched, and never runs `dotnet test` without a project argument.
- **`setup apply` proposes `dotnet test {tests}`** when the detected runner is `dotnet test`, and its baseline runs `dotnet test` once per test project. Maven and Gradle still get no `test-command`.
