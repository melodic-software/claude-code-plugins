# Python Build Commands

## Lint

```bash
# Check (CI mode — no auto-fix)
cd "$PROJECT_DIR" && uv run ruff check . --no-fix

# Fix
cd "$PROJECT_DIR" && uv run ruff check . --fix
```

## Format

```bash
# Check (CI mode)
cd "$PROJECT_DIR" && uv run ruff format . --check

# Fix
cd "$PROJECT_DIR" && uv run ruff format .
```

## Test

```bash
cd "$PROJECT_DIR" && uv run pytest tests/ -x -q
```

## Type check

Part of `check-cmd` (no fix mode — `fix-cmd` only runs the two ruff commands):

```bash
cd "$PROJECT_DIR" && uv run pyright
```

pyright is a **hard prerequisite** of the python default once ruff config opts the ecosystem in — it shares the single compound `check-cmd` with ruff, and tool presence is evaluated per ecosystem, not per tool. On a ruff-configured project with pyright absent, the whole ecosystem reports a missing-tool `skip` (dropping ruff coverage too) rather than skipping pyright alone. Install pyright alongside ruff (see the ecosystem's `install-hint`).

## Gotchas

- **Use `uv run` prefix in uv-managed projects** (a `uv.lock` is the signal) — it ensures the managed virtualenv is used. In pip/poetry projects, use that project's documented invocation instead
- **E501 (line-too-long) is not auto-fixable** — the formatter handles code wrapping, but docstrings/comments/string literals exceeding the configured `line-length` must be shortened manually
- **pyright runs in its default standard mode absent a `pyrightconfig.json` or `pyproject.toml [tool.pyright]`** — on an untyped or partially-typed project this can surface genuine type errors; set `typeCheckingMode` (e.g. `basic` or `off`) or add project config to tune the strictness rather than suppressing findings ad hoc
- **Run from project directory** — each `pyproject.toml` defines an independent project root. Always `cd` to the directory containing `pyproject.toml` before running commands
- **`encoding='utf-8'`** — always specify on Windows `open()` calls

## Project discovery

Find all Python projects dynamically:

```bash
find "$REPO_ROOT" -name "pyproject.toml" -not -path "*/node_modules/*" -not -path "*/.venv/*"
```
