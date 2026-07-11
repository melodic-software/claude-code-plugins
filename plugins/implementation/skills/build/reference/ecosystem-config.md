# Ecosystem config — build

Per-ecosystem build/test/lint configuration. The `/build` skill reads this to detect affected ecosystems from `git status --porcelain` (via `globs`), run each ecosystem's commands, and render the results table.

**Consumer overrides win.** These are portable defaults. When the consuming project documents its own build/test/lint commands (in its `CLAUDE.md`, rules, or a commands reference), those commands replace the defaults below — including any repo-specific gates the project defines (lockfile checks, generated-artifact freshness, CI-parity checks). Never run a default when the project names a different command for the same job.

Map keyed by ecosystem identifier. Sub-keys:

- `enabled` — whether this ecosystem applies (an ecosystem with no matching files in the repo is effectively disabled)
- `globs` — file glob patterns that trigger this ecosystem's auto-detection
- `build-cmd` — build verification command; `null` when the ecosystem has no build step
- `test-cmd` — test command; `null` when no test framework is wired
- `lint-cmd` — lint/format check command; `null` when lint is outsourced to `/lint`
- `anchor` — how to resolve `<solution-or-project-file>`: the scoping anchor for ecosystems with a canonical entry point
- `project-discovery` — file patterns identifying per-project build roots (walked for `<project-dir>`)
- `install-hint` — cross-platform install command shown when the tool is missing

```yaml
ecosystems:
  dotnet:
    enabled: true
    globs: ["*.cs", "*.csproj", "*.sln", "*.slnx", "*.props", "*.targets"]
    anchor: "the solution file at repo root (*.slnx or *.sln); when none exists, the nearest *.csproj above the changed files"
    build-cmd: 'dotnet build "<solution-or-project-file>"'
    test-cmd: 'dotnet test "<solution-or-project-file>" --no-build'
    lint-cmd: 'dotnet format "<solution-or-project-file>" --verify-no-changes'
    install-hint: "Install .NET SDK from https://dot.net"

  python:
    enabled: true
    globs: ["*.py", "pyproject.toml", "uv.lock"]
    project-discovery: ["pyproject.toml"]
    build-cmd: null  # python has no separate build step; lint/test cover verification
    test-cmd: "uv run pytest -x -q"  # from each project root; plain pytest when the project doesn't use uv
    lint-cmd: "uv run ruff check . --no-fix && uv run ruff format . --check"  # when the project configures ruff
    install-hint: "pip install ruff uv | brew install uv ruff"

  typescript:
    enabled: true
    globs: ["*.ts", "*.tsx", "*.js", "*.jsx", "*.mjs", "package.json", "package-lock.json", "pnpm-lock.yaml", "yarn.lock", "tsconfig*.json"]
    project-discovery: ["package.json"]
    build-cmd: "npx tsc --noEmit"  # when the project has a tsconfig; otherwise the package.json build script
    test-cmd: "the package.json test script (npm test / npx vitest run / npx jest — use what the project configures)"
    lint-cmd: "the project's configured linter (npx biome check . when biome.json exists; npx eslint . when eslint config exists)"
    install-hint: "npm i -g typescript | project-local devDependencies preferred"

  bash:
    enabled: true
    globs: ["*.sh", "*.bash"]
    build-cmd: null  # no build step
    test-cmd: null  # run the project's shell-test runner when it documents one (e.g. bats, or a *.test.sh convention)
    lint-cmd: "shellcheck -x -S warning <files> && shfmt -d <files>"
    install-hint: "winget install ShellCheck.ShellCheck mvdan.shfmt | brew install shellcheck shfmt"

  powershell:
    enabled: true
    globs: ["*.ps1", "*.psm1"]
    build-cmd: null  # no build step
    test-cmd: null  # run the project's Pester suite when it documents one (Invoke-Pester)
    lint-cmd: "pwsh -NoProfile -Command 'Invoke-ScriptAnalyzer -Path . -Recurse'"
    install-hint: "Install-Module -Name PSScriptAnalyzer (pwsh)"

  markdown:
    enabled: true
    globs: ["*.md"]
    build-cmd: null  # lint-only ecosystem
    test-cmd: null
    lint-cmd: "npx markdownlint-cli2 <files>"  # when the project has a markdownlint config
    install-hint: "npm i -g markdownlint-cli2"
```
