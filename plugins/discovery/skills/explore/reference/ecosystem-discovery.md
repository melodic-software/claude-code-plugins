# Ecosystem discovery — explore

Per-ecosystem discovery primitives consumed by the explore skill's Dimensions 3–6
(project structure / test discovery / configuration & build state / environment).

Sub-keys:

- `test-globs` — glob patterns identifying test projects / files (Dimension 4)
- `build-configs` — build / package / config files to read when exploring
  "Configuration and build state" (Dimension 5)
- `dependency-grep` — token / regex grepped across project files to map the
  dependency graph (Dimension 3)
- `runtime-version-cmd` — command to check the installed runtime version (Dimension 6)

Use only the ecosystems the consuming repo actually contains. Where the consuming
project's own conventions differ (a custom test layout, a nonstandard workspace
file), the project's conventions win — this table is the generic starting point.

```yaml
ecosystems:
  dotnet:
    test-globs:
      - "**/*Tests*/*.csproj"
      - "**/*.Tests/*.csproj"
    build-configs:
      - "Directory.Build.props"
      - "Directory.Build.targets"
      - "Directory.Packages.props"
      - "global.json"
      - "*.sln"
      - "*.slnx"
      - "*.csproj"
    dependency-grep: "ProjectReference"
    runtime-version-cmd: "dotnet --version"

  typescript:
    test-globs:
      - "**/*.test.ts"
      - "**/*.spec.ts"
      - "**/__tests__/**"
    build-configs:
      - "package.json"
      - "tsconfig.json"
      - "pnpm-workspace.yaml"
      - ".nvmrc"
    dependency-grep: "\"dependencies\"|import .* from"
    runtime-version-cmd: "node --version"

  python:
    test-globs:
      - "**/test_*.py"
      - "**/tests/*.py"
    build-configs:
      - "pyproject.toml"
      - "requirements*.txt"
      - ".python-version"
    dependency-grep: "^import |^from "
    runtime-version-cmd: "python --version"

  go:
    test-globs:
      - "**/*_test.go"
    build-configs:
      - "go.mod"
      - "go.work"
    dependency-grep: "^\\s*\"[^\"]+\"$ in import blocks"
    runtime-version-cmd: "go version"

  rust:
    test-globs:
      - "**/tests/*.rs"
      - "#[cfg(test)] modules in src"
    build-configs:
      - "Cargo.toml"
      - "Cargo.lock"
    dependency-grep: "^use |\\[dependencies\\]"
    runtime-version-cmd: "rustc --version"

  java:
    test-globs:
      - "**/src/test/java/**/*.java"
    build-configs:
      - "pom.xml"
      - "build.gradle"
      - "build.gradle.kts"
      - "settings.gradle*"
    dependency-grep: "<dependency>|implementation\\("
    runtime-version-cmd: "java --version"
```
