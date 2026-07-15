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

## Type check (when configured)

```bash
cd "$PROJECT_DIR" && uv run pyright
```

## Gotchas

- **Use `uv run` prefix in uv-managed projects** (a `uv.lock` is the signal) — it ensures the managed virtualenv is used. In pip/poetry projects, use that project's documented invocation instead
- **E501 (line-too-long) is not auto-fixable** — the formatter handles code wrapping, but docstrings/comments/string literals exceeding the configured `line-length` must be shortened manually
- **Run from project directory** — each `pyproject.toml` defines an independent project root. Always `cd` to the directory containing `pyproject.toml` before running commands
- **`encoding='utf-8'`** — always specify on Windows `open()` calls

## Project discovery

Find all Python projects dynamically:

```bash
find "$REPO_ROOT" -name "pyproject.toml" -not -path "*/node_modules/*" -not -path "*/.venv/*"
```
