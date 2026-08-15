# Ecosystem discovery — explore

Per-ecosystem discovery primitives consumed by the explore skill's Dimensions 3–6
(project structure / test discovery / configuration & build state / environment).

## Prefer the toolchain seam

When the `toolchain` plugin is installed, compose `/toolchain:check`'s ecosystem
detection and command-resolution seam for the shared signal vocabulary it owns —
do not bake a second inventory of those signals. `/toolchain:check` is the
reference skill other plugins compose for that concern instead of baking their
own tables. Gate and fallback follow `docs/conventions/seam-phrasing/README.md`.

Resolve each ecosystem through the ladder `/toolchain:check` documents (consumer
`.claude/ecosystems/<ecosystem>.yaml` authoritative when present; bundled
portable defaults only as that ladder's final rung). Read *resolved* state: an
ecosystem present but `enabled: false` is not configured for exploration either.

| Explore need | Source when `toolchain` is installed |
|---|---|
| Which ecosystems are in play | Resolved `globs` (and covered-ecosystem set), **plus** fallback-table ecosystems the seam does not cover (`rust`, `java` today — `/toolchain:check` covers `dotnet`, `python`, `typescript`, `bash`, `powershell`, `markdown`, `go`) when their fallback `build-configs` markers are present in the repo |
| Project / workspace roots (Dimension 3 adjacency) | Resolved `project-discovery` / `anchor` |
| Build / package / config files to read (Dimension 5) | Explore-owned `build-configs` from the fallback table — seam `globs` / `project-discovery` / `anchor` classify changed files and locate roots; they are not an exhaustive configuration inventory |
| Runtime / toolchain presence (Dimension 6) | Explore-owned `runtime-version-cmd` from the fallback table — resolved `install-hint` is free-form install prose, not a version probe |

**Explore-only keys the seam does not own.** `dependency-grep`, `test-globs`,
`test-content-grep`, `build-configs`, and `runtime-version-cmd` have no home in
the ecosystem-commands surface (or the seam's fields are classifiers / install
prose rather than these inventories). Use the fallback table below for those
keys even when composing the toolchain seam for covered-ecosystem detection and
project-root adjacency.

Where the consuming project's own conventions differ (a custom test layout, a
nonstandard workspace file), the project's conventions win.

## Fallback — toolchain absent

When the `toolchain` plugin is not installed, use the table below for every
sub-key. This is the documented standalone fallback, not a peer source of truth
alongside the seam.

Use only the ecosystems the consuming repo actually contains. Where the consuming
project's own conventions differ (a custom test layout, a nonstandard workspace
file), the project's conventions win — this table is the generic starting point.

Sub-keys:

- `test-globs` — glob patterns identifying test projects / files (Dimension 4)
- `test-content-grep` — content regex for ecosystems that keep tests inside
  source files, where no glob can find them (Dimension 4; only where needed)
- `build-configs` — build / package / config files to read when exploring
  "Configuration and build state" (Dimension 5)
- `dependency-grep` — content regex grepped across source / project files to map
  the dependency graph (Dimension 3)
- `runtime-version-cmd` — command to check the installed runtime version (Dimension 6)

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
      - "**/*.test.{ts,tsx,js,jsx}"
      - "**/*.spec.{ts,tsx,js,jsx}"
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
    # Go imports span multi-line import ( ... ) blocks; the second alternative
    # matches the quoted module paths inside them.
    dependency-grep: "^import |^\\s*\"[A-Za-z0-9._~/-]+\"$"
    runtime-version-cmd: "go version"

  rust:
    test-globs:
      - "**/tests/*.rs"
    test-content-grep: "#\\[cfg\\(test\\)\\]"
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
