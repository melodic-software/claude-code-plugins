# Ecosystem discovery — explore

Per-ecosystem discovery primitives consumed by the explore skill's Dimensions 3–6
(project structure / test discovery / configuration & build state / environment).

## Prefer the toolchain seam

When the `toolchain` plugin is installed, compose `/toolchain:check`'s ecosystem
detection and command-resolution seam for the shared signal vocabulary — do not
bake a second inventory of ecosystems, build/config anchors, or runtime probes.
`/toolchain:check` is the reference skill other plugins compose for that concern
instead of baking their own tables. Gate and fallback follow
`docs/conventions/seam-phrasing/README.md`.

Resolve each ecosystem through the ladder `/toolchain:check` documents (consumer
`.claude/ecosystems/<ecosystem>.yaml` authoritative when present; bundled
portable defaults only as that ladder's final rung). Read *resolved* state: an
ecosystem present but `enabled: false` is not configured for exploration either.

| Explore need | Compose from the toolchain seam |
|---|---|
| Which ecosystems are in play | Resolved `globs` (and covered-ecosystem set) |
| Project / workspace roots (Dimension 3 adjacency) | Resolved `project-discovery` / `anchor` |
| Build / package / config files to read (Dimension 5) | Resolved `project-discovery`, `anchor`, and config-bearing entries in `globs` |
| Runtime / toolchain presence (Dimension 6) | Tools named by resolved `install-hint` and the ecosystem's native version probe — not a parallel `runtime-version-cmd` table |

**Explore-only keys the seam does not own.** `dependency-grep`, `test-globs`, and
`test-content-grep` have no home in the ecosystem-commands surface. Use the
fallback table below for those keys even when composing the toolchain seam for
the shared vocabulary above.

Where the consuming project's own conventions differ (a custom test layout, a
nonstandard workspace file), the project's conventions win.

## Fallback — toolchain absent

When the `toolchain` plugin is not installed, use the table below for every
sub-key. This is the documented standalone fallback, not a peer source of truth
alongside the seam.

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
