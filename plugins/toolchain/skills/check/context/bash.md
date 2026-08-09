# Bash Build Commands

Bash has no build step — shell tests, static analysis, and formatting.

## Test (shell test runner)

Use the consuming project's documented shell-test runner when it has one (a `*.test.sh` discovery script, bats, or similar). When none is documented, there is no default — report `—` for the test column.

**CI-environment caveat:** shell tests can pass locally and fail in CI when they depend on environment differences (installed SDKs, tool output formatting, pruned packages). When local pass + CI fail, suspect a CI-environment-specific assumption before assuming a real bug.

## Lint (ShellCheck)

```bash
shellcheck -x -S warning <files>
```

## Format (shfmt)

```bash
# Check (CI mode)
shfmt -d <files>

# Fix
shfmt -w <files>
```

shfmt reads `.editorconfig` for style; only format when the repo opts in with shell settings there or documents shfmt usage.

## Gotchas

- **ShellCheck version drift** — CI runners may ship an older ShellCheck than the repo's `.shellcheckrc` assumes; optional checks differ across versions
- **`-x` flag** — enables following `source`d files for cross-file analysis
- **`-S warning`** — sets minimum severity to warning (excludes info/style)
- **Use absolute paths** — ShellCheck and shfmt operate on individual files, not directories
- **shfmt absent is a `FAIL`, not a missing-tool `skip`** — `check-cmd` is the single opaque string `shellcheck -x -S warning <files> && shfmt -d <files>`, and the preflight probes the ecosystem's tool, never each sub-tool. So on a project with ShellCheck installed, shfmt absent, and the `.editorconfig` shell-style opt-in met, nothing skips: ShellCheck runs and passes, then `shfmt -d` fails to spawn and the ecosystem reports Lint **`FAIL`**. Because `check-cmd` is one string, that FAIL cannot be narrowed to shfmt alone. Install shfmt alongside ShellCheck (see the ecosystem's `install-hint`), or drop it by overriding `check-cmd` in the consumer's own `.claude/ecosystems/bash.yaml`. Same shape as python's `pyright` behind `uv` (`context/python.md`)

## File discovery

Discover dynamically:

```bash
find "$REPO_ROOT" -name "*.sh" -not -path "*/node_modules/*" -not -path "*/.venv/*" -not -path "*/bin/*" -not -path "*/obj/*"
```
