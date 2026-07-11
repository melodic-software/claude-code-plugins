# Ecosystem lint configuration

Per-ecosystem lint configuration for `/lint`: which ecosystems the skill knows about, how each is detected, and the check/fix commands it runs.

**Consumer overrides win.** These are portable defaults keyed to each tool's own config-file opt-in. When the consuming project documents its own lint commands or config, those govern — never run a linter the project hasn't opted into (running Biome on an ESLint repo, or markdownlint without a config, produces noise, not signal).

The map is keyed by ecosystem identifier. Sub-keys:

- `enabled` — whether this ecosystem applies (no matching files → effectively disabled)
- `globs` — file glob patterns that trigger auto-detection from `git status --porcelain`
- `opt-in` — the config file whose presence signals the project uses this tool
- `check-cmd` — shell command run in check mode (no file modification); `$REPO_ROOT` anchors the repo root
- `fix-cmd` — shell command run in fix mode (`--fix`); `null` means no auto-fix support
- `project-discovery` — optional per-project lint roots (e.g. `pyproject.toml` for python's per-project walk)
- `install-hint` — cross-platform install command shown when the tool is missing (missing tool reports `skip`, never `FAIL`)

```yaml
ecosystems:
  dotnet:
    globs: ["*.cs", "*.csproj", "*.sln", "*.slnx", "*.props", "*.targets"]
    opt-in: "any .NET project (dotnet format ships with the SDK)"
    check-cmd: 'dotnet format "$REPO_ROOT/<solution-or-project-file>" --verify-no-changes'
    fix-cmd: 'dotnet format "$REPO_ROOT/<solution-or-project-file>"'
    install-hint: "Install .NET SDK from https://dot.net"

  python:
    globs: ["*.py", "pyproject.toml", "uv.lock"]
    opt-in: "ruff config (ruff.toml, .ruff.toml, or pyproject.toml [tool.ruff])"
    project-discovery: ["pyproject.toml"]
    check-cmd: "uv run ruff check . --no-fix && uv run ruff format . --check"  # plain ruff when the project doesn't use uv
    fix-cmd: "uv run ruff check . --fix && uv run ruff format ."
    install-hint: "pip install ruff uv | brew install uv ruff"

  typescript:
    globs: ["*.ts", "*.tsx", "*.js", "*.jsx", "*.mjs"]
    opt-in: "biome.json → Biome; eslint config → ESLint (use whichever the project configures)"
    project-discovery: ["package.json"]
    check-cmd: "npx biome check ."
    fix-cmd: "npx biome check --write ."
    install-hint: "project-local devDependencies preferred; npm i -g @biomejs/biome"

  bash:
    globs: ["*.sh", "*.bash"]
    opt-in: "shellcheck always applies to shell files; shfmt only when .editorconfig declares shell style"
    check-cmd: "shellcheck -x -S warning <files> && shfmt -d <files>"
    fix-cmd: "shfmt -w <files>  # shellcheck has no fix mode"
    install-hint: "winget install ShellCheck.ShellCheck mvdan.shfmt | brew install shellcheck shfmt"

  powershell:
    globs: ["*.ps1", "*.psm1"]
    opt-in: "PSScriptAnalyzerSettings.psd1 (or any PowerShell files with pwsh available)"
    check-cmd: "pwsh -NoProfile -Command 'Invoke-ScriptAnalyzer -Path . -Recurse'"
    fix-cmd: null
    install-hint: "Install-Module -Name PSScriptAnalyzer (pwsh)"

  markdown:
    globs: ["*.md"]
    opt-in: "a markdownlint config (.markdownlint*, .markdownlint-cli2.*)"
    check-cmd: "npx markdownlint-cli2 <files>"
    fix-cmd: "npx markdownlint-cli2 --fix <files>"
    install-hint: "npm i -g markdownlint-cli2"

  yaml:
    globs: [".github/**/*.yml", ".github/**/*.yaml"]
    opt-in: "GitHub Actions workflows present"
    check-cmd: |
      actionlint .github/workflows/*.yml
      # plus any schema checks the project documents (check-jsonschema against its own config files)
      # zizmor workflow-security scan when the project uses it — advisory only
    fix-cmd: null
    install-hint: |
      actionlint: winget install rhysd.actionlint | brew install actionlint
      check-jsonschema: pip install check-jsonschema
      zizmor: pip install zizmor

  cross-cutting:
    globs: ["**"]  # any text file change
    opt-in: "each tool's own config at repo root (_typos.toml, .gitleaks.toml, .editorconfig-checker.json / .editorconfig)"
    check-cmd: |
      typos
      gitleaks detect --source . --redact --no-banner --no-git
      # editorconfig-checker — binary name varies by install method (ec / editorconfig-checker / ec-windows-amd64)
      "$EC_BIN"
    fix-cmd: null
    install-hint: |
      typos: winget install Crate-CI.Typos | brew install typos-cli
      gitleaks: winget install Gitleaks.Gitleaks | brew install gitleaks
      editorconfig-checker: winget install EditorConfig-Checker.EditorConfig-Checker | brew install editorconfig-checker
```
